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

@MainActor
public final class AutoStartManager: ObservableObject {

    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var status: AutoStartStatus = .notRegistered
    @Published public private(set) var requiresApproval: Bool = false
    @Published public private(set) var isDenied: Bool = false
    @Published public private(set) var hasApprovalIssue: Bool = false

    private final class SimulatedState {
        var status: SMAppService.Status
        init(status: SMAppService.Status) {
            self.status = status
        }
    }

    private let statusProvider: @MainActor () -> SMAppService.Status
    private let performRegister: @MainActor () throws -> Void
    private let performUnregister: @MainActor () throws -> Void
    private let performOpenSettings: @MainActor () -> Void

    public init(service: SMAppService = .mainApp) {
        self.statusProvider = { service.status }
        self.performRegister = { try service.register() }
        self.performUnregister = { try service.unregister() }
        self.performOpenSettings = { SMAppService.openSystemSettingsLoginItems() }
        refreshStatus()
    }

    internal init(
        status: SMAppService.Status = .notRegistered,
        statusProvider: (@MainActor () -> SMAppService.Status)? = nil,
        registerAction: (@MainActor () throws -> Void)? = nil,
        unregisterAction: (@MainActor () throws -> Void)? = nil,
        openSettingsAction: @escaping @MainActor () -> Void = {}
    ) {
        let state = SimulatedState(status: status)

        if let statusProvider {
            self.statusProvider = statusProvider
        } else {
            self.statusProvider = { state.status }
        }
        self.performRegister = registerAction ?? { state.status = .enabled }
        self.performUnregister = unregisterAction ?? { state.status = .notRegistered }
        self.performOpenSettings = openSettingsAction
        refreshStatus()
    }

    public func refreshStatus() {
        let currentStatus = statusProvider()
        self.status = AutoStartStatus(serviceStatus: currentStatus)
        self.isEnabled = (currentStatus == .enabled)
        self.requiresApproval = (currentStatus == .requiresApproval)
        if currentStatus == .enabled {
            self.isDenied = false
        }
        self.hasApprovalIssue = requiresApproval || isDenied
    }

    public func register() throws {
        do {
            try performRegister()
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
            try performUnregister()
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
        performOpenSettings()
    }
}
