import Foundation
import Combine
import ServiceManagement

public enum AutoStartStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound

    public init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notRegistered:
            self = .notRegistered
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notRegistered
        }
    }
}

public protocol AutoStartServiceRepresentable: AnyObject, Sendable {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

public final class SystemAutoStartService: AutoStartServiceRepresentable, @unchecked Sendable {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var status: SMAppService.Status {
        service.status
    }

    public func register() throws {
        try service.register()
    }

    public func unregister() throws {
        try service.unregister()
    }

    public func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
public final class AutoStartManager: ObservableObject {

    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var status: AutoStartStatus = .notRegistered
    @Published public private(set) var requiresApproval: Bool = false
    @Published public private(set) var isDenied: Bool = false

    public var hasApprovalIssue: Bool {
        requiresApproval || isDenied
    }

    private let service: AutoStartServiceRepresentable

    public init(service: AutoStartServiceRepresentable = SystemAutoStartService()) {
        self.service = service
        refreshStatus()
    }

    public func refreshStatus() {
        let currentStatus = service.status
        self.status = AutoStartStatus(serviceStatus: currentStatus)
        self.isEnabled = (currentStatus == .enabled)
        self.requiresApproval = (currentStatus == .requiresApproval)
        if currentStatus == .enabled {
            self.isDenied = false
        }
    }

    public func register() throws {
        do {
            try service.register()
            self.isDenied = false
            refreshStatus()
        } catch {
            self.isDenied = true
            refreshStatus()
            throw error
        }
    }

    public func unregister() throws {
        do {
            try service.unregister()
            self.isDenied = false
            refreshStatus()
        } catch {
            refreshStatus()
            throw error
        }
    }

    public func toggle() throws {
        if isEnabled {
            try unregister()
        } else {
            try register()
        }
    }

    public func openSystemSettings() {
        service.openSystemSettingsLoginItems()
    }
}
