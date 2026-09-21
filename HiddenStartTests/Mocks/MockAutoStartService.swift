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
