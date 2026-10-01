import Testing
@testable import Vesila

@Suite("Login item coordination")
@MainActor
struct LoginItemControllerTests {
    @Test(arguments: [LoginItemStatus.notRegistered, .enabled, .requiresApproval, .notFound])
    func reflectsActualStatus(status: LoginItemStatus) {
        let service = FakeLoginItemService(status: status)
        let controller = LoginItemController(service: service)
        #expect(controller.status == status)
        #expect(controller.status.isEnabled == (status == .enabled))
        service.status = .enabled
        #expect(controller.status.isEnabled, "external OS changes are read without cached preferences")
        service.status = .notRegistered
        #expect(!controller.status.isEnabled)
    }

    @Test func enableAndDisableUseSystemRegistration() {
        let service = FakeLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)
        let enabled = controller.setEnabled(true)
        #expect(enabled.status == .enabled)
        #expect(enabled.error == nil)
        #expect(service.registrations == 1)
        let disabled = controller.setEnabled(false)
        #expect(disabled.status == .notRegistered)
        #expect(disabled.error == nil)
        #expect(service.unregistrations == 1)
    }

    @Test func approvalIsOffAndDoesNotReregister() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registrationStatus = .requiresApproval
        let controller = LoginItemController(service: service)
        let result = controller.setEnabled(true)
        #expect(result.status == .requiresApproval)
        #expect(!result.status.isEnabled)
        #expect(controller.setEnabled(true).status == .requiresApproval)
        #expect(service.registrations == 1)
        #expect(controller.setEnabled(false).status == .notRegistered)
        #expect(service.unregistrations == 1)
    }

    @Test(arguments: [true, false])
    func errorsPreserveActualSystemState(enabling: Bool) {
        let initial: LoginItemStatus = enabling ? .notRegistered : .enabled
        let service = FakeLoginItemService(status: initial)
        service.shouldFail = true
        let result = LoginItemController(service: service).setEnabled(enabling)
        #expect(result.error != nil)
        #expect(result.status == initial)
    }

    @Test func readsResultingStatusEvenIfOperationThrows() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.shouldFail = true
        service.statusOnFailure = .requiresApproval
        let result = LoginItemController(service: service).setEnabled(true)
        #expect(result.error != nil)
        #expect(result.status == .requiresApproval)
        #expect(!result.status.isEnabled)
    }

    @Test func successfulOperationDoesNotAssumeRequestedState() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registrationStatus = .notFound
        let result = LoginItemController(service: service).setEnabled(true)
        #expect(result.error == nil)
        #expect(result.status == .notFound)
        #expect(!result.status.isEnabled)
    }

    @Test func matchingStateDoesNotRepeatOperations() {
        let service = FakeLoginItemService(status: .enabled)
        let controller = LoginItemController(service: service)
        _ = controller.setEnabled(true)
        #expect(service.registrations == 0)
        service.status = .notRegistered
        _ = controller.setEnabled(false)
        #expect(service.unregistrations == 0)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    enum Failure: Error { case unavailable }
    var status: LoginItemStatus
    var registrationStatus: LoginItemStatus = .enabled
    var statusOnFailure: LoginItemStatus?
    var shouldFail = false
    var registrations = 0
    var unregistrations = 0

    init(status: LoginItemStatus) { self.status = status }

    func register() throws {
        registrations += 1
        try checkFailure()
        status = registrationStatus
    }

    func unregister() throws {
        unregistrations += 1
        try checkFailure()
        status = .notRegistered
    }

    private func checkFailure() throws {
        if shouldFail {
            if let statusOnFailure { status = statusOnFailure }
            throw Failure.unavailable
        }
    }
}
