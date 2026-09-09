import Foundation
import ServiceManagement
@testable import HiddenStart

public final class MockAutoStartService: AutoStartServiceRepresentable, @unchecked Sendable {
    public var mockStatus: SMAppService.Status
    public var registerCalled = false
    public var unregisterCalled = false
    public var openSystemSettingsCalled = false
    public var registerError: (any Error)?
    public var unregisterError: (any Error)?

    public init(status: SMAppService.Status = .notRegistered) {
        self.mockStatus = status
    }

    public var status: SMAppService.Status { mockStatus }

    public func register() throws {
        registerCalled = true
        if let registerError {
            throw registerError
        }
        mockStatus = .enabled
    }

    public func unregister() throws {
        unregisterCalled = true
        if let unregisterError {
            throw unregisterError
        }
        mockStatus = .notRegistered
    }

    public func openSystemSettingsLoginItems() {
        openSystemSettingsCalled = true
    }
}

@MainActor
public final class MockAutoStartManager: AutoStartManaging {
    public var isEnabled: Bool = false
    public var status: AutoStartStatus = .notRegistered
    public var requiresApproval: Bool = false
    public var isDenied: Bool = false

    public var hasApprovalIssue: Bool {
        requiresApproval || isDenied
    }

    public var registerCalled = false
    public var unregisterCalled = false
    public var toggleCalled = false
    public var openSystemSettingsCalled = false
    public var refreshStatusCalled = false

    public var errorToThrow: (any Error)?

    public init(
        isEnabled: Bool = false,
        status: AutoStartStatus = .notRegistered,
        requiresApproval: Bool = false,
        isDenied: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.status = status
        self.requiresApproval = requiresApproval
        self.isDenied = isDenied
    }

    public func register() throws {
        registerCalled = true
        if let errorToThrow { throw errorToThrow }
        isEnabled = true
        status = .enabled
        requiresApproval = false
    }

    public func unregister() throws {
        unregisterCalled = true
        if let errorToThrow { throw errorToThrow }
        isEnabled = false
        status = .notRegistered
        requiresApproval = false
    }

    public func toggle() throws {
        toggleCalled = true
        if let errorToThrow { throw errorToThrow }
        if isEnabled {
            try unregister()
        } else {
            try register()
        }
    }

    public func openSystemSettings() {
        openSystemSettingsCalled = true
    }

    public func refreshStatus() {
        refreshStatusCalled = true
    }
}
