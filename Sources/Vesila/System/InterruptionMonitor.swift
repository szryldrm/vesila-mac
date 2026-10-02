import AppKit
import CoreGraphics

enum VesilaResume {
    case systemWake, screenUnlocked, sessionActivated, lidOpened, clockChanged
}

/// Reports system sleep, screen lock, switching to another user, and closing the laptop lid as a
/// `VesilaInterruption`. It reports every one of them and makes no decisions: `VesilaState` decides
/// whether each one ends the session. Sleep, user switch, and lid close always turn Vesila off; a
/// screen lock does too, unless Stay Active When Locked is on. Every interruption, an ignored lock
/// included, abandons a pending Presence activation. Wake, unlock, session activation, lid reopen,
/// and clock changes report resume events for schedule evaluation, never session restoration.
///
/// Display sleep on its own is deliberately not an interruption. System Awake exists precisely to
/// let the display sleep while the Mac stays awake. When display sleep does lock the screen, the
/// lock notification covers it.
@MainActor
final class InterruptionMonitor: NSObject {
    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")

    private let lidMonitor = LidMonitor()
    private var clockObservers: [NSObjectProtocol] = []
    private var onResume: ((VesilaResume) -> Void)?
    private var onInterruption: ((VesilaInterruption) -> Void)?

    func start(onInterruption: @escaping (VesilaInterruption) -> Void, onResume: @escaping (VesilaResume) -> Void) {
        guard self.onInterruption == nil else { return }
        self.onInterruption = onInterruption
        self.onResume = onResume

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenDidLock), name: Self.screenLockedNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionDidActivate), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenDidUnlock), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            clockObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onResume?(.clockChanged) }
            })
        }
        lidMonitor.start(onLidClosed: { [weak self] in
            self?.onInterruption?(.lidClosed)
        }, onLidOpened: { [weak self] in
            self?.onResume?(.lidOpened)
        })
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        clockObservers.forEach { NotificationCenter.default.removeObserver($0) }
        clockObservers.removeAll()
        lidMonitor.stop()
        onInterruption = nil
        onResume = nil
    }

    /// Seed at launch and refresh on wake, before a potentially delayed lock notification.
    /// Missing session data is treated as unavailable, so a boundary cannot activate on a lock screen.
    nonisolated static func sessionSnapshot() -> (locked: Bool, active: Bool) {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return (true, false) }
        return (session["CGSSessionScreenIsLocked"] as? Bool ?? false,
                session[kCGSessionOnConsoleKey as String] as? Bool ?? false)
    }

    @objc private func systemDidWake() { onResume?(.systemWake) }
    @objc private func sessionDidActivate() { onResume?(.sessionActivated) }
    @objc private func screenDidUnlock() { onResume?(.screenUnlocked) }
    @objc private func systemWillSleep() { onInterruption?(.systemSleep) }
    @objc private func sessionDidResignActive() { onInterruption?(.sessionResigned) }
    @objc private func screenDidLock() { onInterruption?(.screenLocked) }
}
