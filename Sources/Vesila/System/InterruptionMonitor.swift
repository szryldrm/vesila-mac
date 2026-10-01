import AppKit

/// Reports system sleep, screen lock, switching to another user, and closing the laptop lid as a
/// `VesilaInterruption`. It reports every one of them and makes no decisions: `VesilaState` decides
/// whether each one ends the session. Sleep, user switch, and lid close always turn Vesila off; a
/// screen lock does too, unless Stay Active When Locked is on. Every interruption, an ignored lock
/// included, abandons a pending Presence activation. Nothing is reported on wake or unlock, so
/// nothing is ever restored.
///
/// Display sleep on its own is deliberately not an interruption. System Awake exists precisely to
/// let the display sleep while the Mac stays awake. When display sleep does lock the screen, the
/// lock notification covers it.
@MainActor
final class InterruptionMonitor: NSObject {
    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")

    private let lidMonitor = LidMonitor()
    private var onInterruption: ((VesilaInterruption) -> Void)?

    func start(onInterruption: @escaping (VesilaInterruption) -> Void) {
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
