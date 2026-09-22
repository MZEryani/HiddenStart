import Foundation
import Combine

@MainActor
public protocol ManagedAppStoring: AnyObject {
    var apps: [ManagedApp] { get }
    var appsPublisher: AnyPublisher<[ManagedApp], Never> { get }
    func load() throws
    func save() throws
    func addApp(at url: URL) throws -> ManagedApp
    func remove(withId id: UUID) throws
    func update(_ app: ManagedApp) throws
    func isMissing(appId: UUID) -> Bool
}
