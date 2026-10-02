import Foundation
import IOKit
import IOKit.pwr_mgt
import OSLog

/// Watches IOPMrootDomain's clamshell state and reports both close and open edges of the laptop lid.
/// This is the only signal for a lid closing while an external display keeps the Mac awake.
///
/// Use from the main thread; notifications are delivered on the main queue. Not main-actor
/// isolated so that `deinit` can always tear down the IOKit registration, which holds an
/// unretained pointer to this object.
final class LidMonitor {
    private var rootDomain: io_service_t = IO_OBJECT_NULL
    private var notificationPort: IONotificationPortRef?
    private var interestNotification: io_object_t = IO_OBJECT_NULL
    private var lidWasClosed = false
    private var onLidOpened: (@MainActor @Sendable () -> Void)?
    private var onLidClosed: (@MainActor @Sendable () -> Void)?

    func start(onLidClosed: @escaping @MainActor @Sendable () -> Void, onLidOpened: @escaping @MainActor @Sendable () -> Void = {}) {
        guard rootDomain == IO_OBJECT_NULL else { return }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else {
            Logger.vesila.error("IOPMrootDomain not found; lid-close detection is unavailable.")
            return
        }
        // Macs without a lid have no clamshell state; there is nothing to watch.
        guard let isClosed = Self.isLidClosed(service) else {
            IOObjectRelease(service)
            return
        }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            Logger.vesila.error("Could not create an IOKit notification port; lid-close detection is unavailable.")
            IOObjectRelease(service)
            return
        }

        rootDomain = service
        notificationPort = port
        lidWasClosed = isClosed
        self.onLidClosed = onLidClosed
        self.onLidOpened = onLidOpened
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { context, _, _, _ in
                guard let context else { return }
                Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue().clamshellStateMayHaveChanged()
            },
            context,
            &interestNotification
        )
        guard result == kIOReturnSuccess else {
            Logger.vesila.error("Could not observe IOPMrootDomain (IOReturn \(result)); lid-close detection is unavailable.")
            stop()
            return
        }
    }

    func stop() {
        if interestNotification != IO_OBJECT_NULL {
            IOObjectRelease(interestNotification)
            interestNotification = IO_OBJECT_NULL
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if rootDomain != IO_OBJECT_NULL {
            IOObjectRelease(rootDomain)
            rootDomain = IO_OBJECT_NULL
        }
        onLidClosed = nil
        onLidOpened = nil
    }

    deinit {
        stop()
    }

    private func clamshellStateMayHaveChanged() {
        guard rootDomain != IO_OBJECT_NULL, let isClosed = Self.isLidClosed(rootDomain) else { return }
        let wasClosed = lidWasClosed
        lidWasClosed = isClosed
        guard isClosed != wasClosed else { return }
        // The notification port delivers on the main queue (see `start`).
        MainActor.assumeIsolated {
            if isClosed { onLidClosed?() } else { onLidOpened?() }
        }
    }

    private static func isLidClosed(_ rootDomain: io_service_t) -> Bool? {
        guard let property = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return (property.takeRetainedValue() as? NSNumber)?.boolValue
    }
}
