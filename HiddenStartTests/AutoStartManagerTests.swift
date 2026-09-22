import Testing
import Foundation
import ServiceManagement
@testable import HiddenStart

@Suite("AutoStartManager Tests")
@MainActor
struct AutoStartManagerTests {
    @Test("Initializes with notRegistered status correctly")
    func testInitializesNotRegistered() {
        let manager = AutoStartManager(status: .notRegistered)

        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == false)
        #expect(manager.isDenied == false)
        #expect(manager.hasApprovalIssue == false)
        #expect(manager.status == .notRegistered)
    }

    @Test("Initializes with enabled status correctly")
    func testInitializesEnabled() {
        let manager = AutoStartManager(status: .enabled)

        #expect(manager.isEnabled == true)
        #expect(manager.requiresApproval == false)
        #expect(manager.isDenied == false)
        #expect(manager.hasApprovalIssue == false)
        #expect(manager.status == .enabled)
    }

    @Test("Initializes with requiresApproval status correctly")
    func testInitializesRequiresApproval() {
        let manager = AutoStartManager(status: .requiresApproval)

        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == true)
        #expect(manager.isDenied == false)
        #expect(manager.hasApprovalIssue == true)
        #expect(manager.status == .requiresApproval)
    }

    @Test("Initializes with notFound status correctly")
    func testInitializesNotFound() {
        let manager = AutoStartManager(status: .notFound)

        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == false)
        #expect(manager.isDenied == false)
        #expect(manager.hasApprovalIssue == false)
        #expect(manager.status == .notFound)
    }

    @Test("Register succeeds and updates state to enabled")
    func testRegisterSuccess() throws {
        let manager = AutoStartManager(status: .notRegistered)

        try manager.register()

        #expect(manager.isEnabled == true)
        #expect(manager.requiresApproval == false)
        #expect(manager.isDenied == false)
        #expect(manager.hasApprovalIssue == false)
        #expect(manager.status == .enabled)
    }

    @Test("Unregister succeeds and updates state to notRegistered")
    func testUnregisterSuccess() throws {
        let manager = AutoStartManager(status: .enabled)

        try manager.unregister()

        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == false)
        #expect(manager.isDenied == false)
        #expect(manager.hasApprovalIssue == false)
        #expect(manager.status == .notRegistered)
    }

    @Test("Toggle registers when disabled and unregisters when enabled")
    func testToggle() throws {
        let manager = AutoStartManager(status: .notRegistered)

        try manager.toggle()
        #expect(manager.isEnabled == true)
        #expect(manager.status == .enabled)

        try manager.toggle()
        #expect(manager.isEnabled == false)
        #expect(manager.status == .notRegistered)
    }

    @Test("Register throws error when service fails and marks as denied")
    func testRegisterFailure() {
        struct TestError: Error, Equatable {}
        let manager = AutoStartManager(
            status: .notRegistered,
            registerAction: { throw TestError() }
        )

        #expect(throws: TestError.self) {
            try manager.register()
        }
        #expect(manager.isEnabled == false)
        #expect(manager.isDenied == true)
        #expect(manager.hasApprovalIssue == true)
        #expect(manager.status == .notRegistered)
    }

    @Test("Unregister throws error when service fails")
    func testUnregisterFailure() {
        struct TestError: Error, Equatable {}
        let manager = AutoStartManager(
            status: .enabled,
            unregisterAction: { throw TestError() }
        )

        #expect(throws: TestError.self) {
            try manager.unregister()
        }
        #expect(manager.isEnabled == true)
        #expect(manager.status == .enabled)
    }

    @Test("openSystemSettings forwards to action")
    func testOpenSystemSettings() {
        var openSettingsCalled = false
        let manager = AutoStartManager(
            status: .requiresApproval,
            openSettingsAction: { openSettingsCalled = true }
        )

        manager.openSystemSettings()

        #expect(openSettingsCalled == true)
    }

    @Test("statusProvider hook dynamically informs refreshStatus")
    func testStatusProviderDynamicHook() {
        final class DynamicBox {
            var status: SMAppService.Status
            init(status: SMAppService.Status) { self.status = status }
        }
        let box = DynamicBox(status: .notRegistered)
        let manager = AutoStartManager(
            status: box.status,
            statusProvider: { box.status }
        )

        #expect(manager.isEnabled == false)
        #expect(manager.status == .notRegistered)

        box.status = .enabled
        manager.refreshStatus()

        #expect(manager.isEnabled == true)
        #expect(manager.status == .enabled)
    }
}
