import AppKit

/// Reports the events after which Vesila turns itself off: system sleep, screen lock, switching to
/// another user, and closing the laptop lid. Nothing is reported on wake or unlock; Vesila stays off.
///
/// Display sleep on its own is deliberately not an interruption. System Awake without Keep
/// Display Awake exists precisely to let the display sleep while the Mac stays awake. When display
/// sleep does lock the screen, the lock notification covers it.
@MainActor
final class InterruptionMonitor: NSObject {
    enum Interruption: String {
        case systemSleep
        case screenLocked
        case sessionResigned
        case lidClosed
    }

    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")

    private let lidMonitor = LidMonitor()
    private var onInterruption: ((Interruption) -> Void)?

    func start(onInterruption: @escaping (Interruption) -> Void) {
        guard self.onInterruption == nil else { return }
        self.onInterruption = onInterruption

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenDidLock), name: Self.screenLockedNotification, object: nil)
        lidMonitor.start { [weak self] in
            self?.onInterruption?(.lidClosed)
        }
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        lidMonitor.stop()
        onInterruption = nil
    }

    @objc private func systemWillSleep() { onInterruption?(.systemSleep) }
    @objc private func sessionDidResignActive() { onInterruption?(.sessionResigned) }
    @objc private func screenDidLock() { onInterruption?(.screenLocked) }
}
