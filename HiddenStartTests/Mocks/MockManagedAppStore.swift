import Foundation
import Combine
@testable import HiddenStart

@MainActor
public final class MockManagedAppStore: ManagedAppStoring {
    @Published public var apps: [ManagedApp] = []

    public var appsPublisher: AnyPublisher<[ManagedApp], Never> {
        $apps.eraseToAnyPublisher()
    }

    public var saveCallCount = 0
    public var loadCallCount = 0
    public var missingIds: Set<UUID> = []
    public var appToReturnFromAddApp: ManagedApp?

    public init(apps: [ManagedApp] = [], missingIds: Set<UUID> = []) {
        self.apps = apps
        self.missingIds = missingIds
    }

    public func load() throws {
        loadCallCount += 1
    }

    public func save() throws {
        saveCallCount += 1
    }

    public func addApp(at url: URL) throws -> ManagedApp {
        if let preset = appToReturnFromAddApp {
            apps.append(preset)
            try save()
            return preset
        }
        let app = AppPreset.makeManagedApp(
            name: url.deletingPathExtension().lastPathComponent,
            bundlePath: url.path,
            bundleIdentifier: nil
        )
        apps.append(app)
        try save()
        return app
    }

    public func add(_ app: ManagedApp) throws {
        apps.append(app)
        try save()
    }

    public func remove(withId id: UUID) throws {
        apps.removeAll { $0.id == id }
        missingIds.remove(id)
        try save()
    }

    public func update(_ app: ManagedApp) throws {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index] = app
            try save()
        }
    }

    public func isMissing(appId: UUID) -> Bool {
        missingIds.contains(appId)
    }
}
