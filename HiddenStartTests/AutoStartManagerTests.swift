import Testing
import Foundation
import ServiceManagement
@testable import HiddenStart

@Suite("AutoStartManager Tests")
@MainActor
struct AutoStartManagerTests {
    @Test("Initializes with notRegistered status correctly")
    func testInitializesNotRegistered() {
        let mockService = MockAutoStartService(status: .notRegistered)
        let manager = AutoStartManager(service: mockService)

        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == false)
        #expect(manager.status == .notRegistered)
    }

    @Test("Initializes with enabled status correctly")
    func testInitializesEnabled() {
        let mockService = MockAutoStartService(status: .enabled)
        let manager = AutoStartManager(service: mockService)

        #expect(manager.isEnabled == true)
        #expect(manager.requiresApproval == false)
        #expect(manager.status == .enabled)
    }

    @Test("Initializes with requiresApproval status correctly")
    func testInitializesRequiresApproval() {
        let mockService = MockAutoStartService(status: .requiresApproval)
        let manager = AutoStartManager(service: mockService)

        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == true)
        #expect(manager.status == .requiresApproval)
    }

    @Test("Initializes with notFound status correctly")
    func testInitializesNotFound() {
        let mockService = MockAutoStartService(status: .notFound)
        let manager = AutoStartManager(service: mockService)

        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == false)
        #expect(manager.status == .notFound)
    }

    @Test("Register succeeds and updates state to enabled")
    func testRegisterSuccess() throws {
        let mockService = MockAutoStartService(status: .notRegistered)
        let manager = AutoStartManager(service: mockService)

        try manager.register()

        #expect(mockService.registerCalled == true)
        #expect(manager.isEnabled == true)
        #expect(manager.requiresApproval == false)
        #expect(manager.status == .enabled)
    }

    @Test("Unregister succeeds and updates state to notRegistered")
    func testUnregisterSuccess() throws {
        let mockService = MockAutoStartService(status: .enabled)
        let manager = AutoStartManager(service: mockService)

        try manager.unregister()

        #expect(mockService.unregisterCalled == true)
        #expect(manager.isEnabled == false)
        #expect(manager.status == .notRegistered)
    }

    @Test("Toggle registers when disabled and unregisters when enabled")
    func testToggle() throws {
        let mockService = MockAutoStartService(status: .notRegistered)
        let manager = AutoStartManager(service: mockService)

        try manager.toggle()
        #expect(mockService.registerCalled == true)
        #expect(manager.isEnabled == true)

        try manager.toggle()
        #expect(mockService.unregisterCalled == true)
        #expect(manager.isEnabled == false)
    }

    @Test("Register throws error when service fails")
    func testRegisterFailure() {
        struct TestError: Error, Equatable {}
        let mockService = MockAutoStartService(status: .notRegistered)
        mockService.registerError = TestError()
        let manager = AutoStartManager(service: mockService)

        #expect(throws: TestError.self) {
            try manager.register()
        }
        #expect(manager.isEnabled == false)
    }

    @Test("Unregister throws error when service fails")
    func testUnregisterFailure() {
        struct TestError: Error, Equatable {}
        let mockService = MockAutoStartService(status: .enabled)
        mockService.unregisterError = TestError()
        let manager = AutoStartManager(service: mockService)

        #expect(throws: TestError.self) {
            try manager.unregister()
        }
        #expect(manager.isEnabled == true)
    }

    @Test("openSystemSettings forwards to service")
    func testOpenSystemSettings() {
        let mockService = MockAutoStartService(status: .requiresApproval)
        let manager = AutoStartManager(service: mockService)

        manager.openSystemSettings()

        #expect(mockService.openSystemSettingsCalled == true)
    }
}
