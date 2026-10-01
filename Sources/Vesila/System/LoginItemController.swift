import ServiceManagement

/// Mirrors the OS registration state. Only `enabled` means login startup is active.
enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isEnabled: Bool { self == .enabled }
}

@MainActor
protocol LoginItemServicing {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
final class MainAppLoginItemService: LoginItemServicing {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Application preference coordination, independent of the activity session and UserDefaults.
@MainActor
final class LoginItemController {
    struct Result {
        let status: LoginItemStatus
        let error: Error?
    }

    private let service: any LoginItemServicing

    init(service: any LoginItemServicing) {
        self.service = service
    }

    var status: LoginItemStatus { service.status }

    func setEnabled(_ enabled: Bool) -> Result {
        var failure: Error?
        do {
            // Pending approval is already registered; repeating registration can fail.
            if enabled {
                if status != .enabled && status != .requiresApproval {
                    try service.register()
                }
            } else if status != .notRegistered {
                try service.unregister()
            }
        } catch {
            failure = error
        }
        // Even a failed operation may have changed system state. Never assume the requested value.
        return Result(status: service.status, error: failure)
    }
}
