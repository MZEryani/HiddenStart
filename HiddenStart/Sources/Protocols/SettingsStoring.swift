import Foundation

@MainActor
public protocol SettingsStoring: AnyObject {
    var apps: [ManagedApp] { get set }
    func load() throws
    func save() throws
    func add(_ app: ManagedApp) throws
    func remove(withId id: UUID) throws
    func update(_ app: ManagedApp) throws
}
