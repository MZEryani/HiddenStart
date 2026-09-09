import Foundation

@MainActor
public final class AppResolver: AppResolving {
    private let fileManager: FileManager
    private let workspaceManager: WorkspaceManaging
    private let fileExistsChecker: (String) -> Bool

    public init(
        fileManager: FileManager = .default,
        workspaceManager: WorkspaceManaging = SystemWorkspaceManager(),
        fileExistsChecker: ((String) -> Bool)? = nil
    ) {
        self.fileManager = fileManager
        self.workspaceManager = workspaceManager
        if let fileExistsChecker {
            self.fileExistsChecker = fileExistsChecker
        } else {
            self.fileExistsChecker = { fileManager.fileExists(atPath: $0) }
        }
    }

    public func resolveApp(_ app: ManagedApp) -> AppResolutionResult {
        if !app.bundlePath.isEmpty && fileExistsChecker(app.bundlePath) {
            return .valid(app)
        }

        guard let bundleId = app.bundleIdentifier, !bundleId.isEmpty else {
            return .missing(app)
        }

        guard let resolvedURL = workspaceManager.urlForApplication(withBundleIdentifier: bundleId),
              fileExistsChecker(resolvedURL.path) else {
            return .missing(app)
        }

        var healedApp = app
        healedApp.bundlePath = resolvedURL.path
        return .healed(healedApp)
    }

    public func resolveAndHeal(apps: [ManagedApp], store: SettingsStoring?) -> [ManagedApp] {
        var results: [ManagedApp] = []
        for app in apps {
            var currentApp = app
            var wasHealed = false

            switch resolveApp(currentApp) {
            case .valid(let validApp):
                currentApp = validApp
            case .healed(let healedApp):
                currentApp = healedApp
                wasHealed = true
            case .missing(let missingApp):
                currentApp = missingApp
            }

            if currentApp.customArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let defaultArgs = AppPreset.defaultArguments(forBundleId: currentApp.bundleIdentifier) {
                currentApp.customArguments = defaultArgs
                wasHealed = true
            }

            if wasHealed {
                try? store?.update(currentApp)
            }
            results.append(currentApp)
        }
        return results
    }
}
