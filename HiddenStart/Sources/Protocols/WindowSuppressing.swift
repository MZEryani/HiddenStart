import Foundation

@MainActor
public protocol WindowSuppressing: AnyObject, Sendable {
    func launch(app: ManagedApp) async throws
    func cancel(appId: UUID)
    func cancel(app: ManagedApp)
    func cancelAll()
}

extension WindowSuppressing {
    public func cancel(app: ManagedApp) {
        cancel(appId: app.id)
    }
}
