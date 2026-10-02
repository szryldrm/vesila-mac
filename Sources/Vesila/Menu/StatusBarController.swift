import AppKit
import ServiceManagement

/// Owns the menu bar item. It renders `VesilaController.state` into the status icon and the open
/// menu, and forwards clicks back to the controller. It holds no application state of its own.
///
/// Left-click opens the menu; right-click is the quick toggle. The menu is attached to the status
/// item only for the duration of one click, since a permanently attached menu would also swallow
/// right-clicks.
@MainActor
final class StatusBarController: NSObject {
    private let controller: VesilaController
    private let loginItemController = LoginItemController(service: MainAppLoginItemService())
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let updaterController: UpdaterController
    private lazy var aboutWindowController = AboutWindowController(updaterController: updaterController)

    private lazy var scheduleWindowController = ScheduleWindowController { [weak self] schedule in
        self?.controller.setSchedule(schedule)
    }

    // Set only while the menu is open. The menu and its view are rebuilt on every open.
    private weak var openMenu: NSMenu?
    private weak var openMenuView: VesilaMenuView?
    private var countdownTimer: Timer?

    init(controller: VesilaController, updaterController: UpdaterController) {
        self.updaterController = updaterController
        self.controller = controller
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel(VesilaConfig.appName)
        }

        controller.onChange = { [weak self] state in
            self?.render(state)
        }
        controller.onAccessibilityRequired = { [weak self] in
            self?.explainAccessibilityRequirement()
        }
        render(controller.state)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            controller.quickToggle()
        } else {
            showMenu()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let menuView = VesilaMenuView(state: controller.state, now: .now, loginItemStatus: loginItemController.status) { [weak self] action in
            self?.handle(action)
        }
        let contentItem = NSMenuItem()
        contentItem.view = menuView
        menu.addItem(contentItem)

        // Hidden item so ⌘Q works while the menu is open.
        let quitItem = NSMenuItem(title: "Quit Vesila", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.isHidden = true
        quitItem.allowsKeyEquivalentWhenHidden = true
        menu.addItem(quitItem)

        openMenu = menu
        openMenuView = menuView
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    private func handle(_ action: VesilaMenuView.Action) {
        switch action {
        case .setVesilaActive(let isOn):
            controller.setVesilaActive(isOn)
        case .setPresence(let isOn):
            controller.setPresenceActive(isOn)
        case .setSystemAwake(let isOn):
            controller.setSystemAwakeActive(isOn)
        case .setStayActiveWhenLocked(let isOn):
            controller.setStayActiveWhenLocked(isOn)
        case .selectActivationMode(let mode):
            controller.selectActivationMode(mode)
        case .editSchedule:
            openMenu?.cancelTracking()
            scheduleWindowController.show(schedule: controller.state.preferences.schedule)
        case .selectDuration(let duration):
            controller.selectDuration(duration)
        case .setStartOnLaunch(let isOn):
            let result = loginItemController.setEnabled(isOn)
            openMenuView?.renderLoginItemStatus(result.status)
            if result.status == .requiresApproval || result.status == .notFound || result.error != nil {
                explainLoginItemResult(result)
            }
        case .showAbout:
            openMenu?.cancelTracking()
            aboutWindowController.show()
        case .quit:
            openMenu?.cancelTracking()
            NSApp.terminate(nil)
        }
    }

    private func render(_ state: VesilaState) {
        statusItem.button?.image = VesilaIconLibrary.statusImage(for: state.activeFeatures)
        openMenuView?.render(state, now: .now)
    }

    private func explainLoginItemResult(_ result: LoginItemController.Result) {
        openMenu?.cancelTracking()
        let alert = NSAlert()
        alert.alertStyle = .warning
        if result.status == .requiresApproval {
            alert.messageText = "Start on Launch Requires Approval"
            alert.informativeText = "Allow Vesila in System Settings > General > Login Items to launch automatically when you sign in. Start on Launch will remain off until macOS reports it as enabled."
            alert.addButton(withTitle: "Open Login Items Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            alert.messageText = "Could Not Change Start on Launch"
            alert.informativeText = result.error?.localizedDescription ?? "macOS could not update Vesila's login item."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func explainAccessibilityRequirement() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "Vesila needs Accessibility access to send a harmless activity signal that keeps apps like Teams from marking you idle. Grant access in System Settings, and Vesila will activate automatically."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AccessibilityPermission.requestAccess()
        controller.activatePresenceWhenAccessibilityGranted()
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        countdownTimer?.invalidate()
        countdownTimer = .scheduledOnMain(interval: 1, repeats: true, owner: self) { statusBar in
            statusBar.openMenuView?.refreshCountdown(statusBar.controller.state, now: .now)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        openMenu = nil
        openMenuView = nil
        // Detach once this click has finished, so the next click reaches `statusItemClicked` again.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }
}
