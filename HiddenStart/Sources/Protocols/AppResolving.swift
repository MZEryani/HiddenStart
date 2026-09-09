import Foundation

public enum AppResolutionResult: Equatable, Sendable {
    case valid(ManagedApp)
    case healed(ManagedApp)
    case missing(ManagedApp)

    public var app: ManagedApp {
        switch self {
        case .valid(let app), .healed(let app), .missing(let app):
            return app
        }
    }

    public var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }

    public var isHealed: Bool {
        if case .healed = self { return true }
        return false
    }
}

@MainActor
public protocol AppResolving: AnyObject {
    func resolveApp(_ app: ManagedApp) -> AppResolutionResult
    func resolveAndHeal(apps: [ManagedApp], store: SettingsStoring?) -> [ManagedApp]
}
