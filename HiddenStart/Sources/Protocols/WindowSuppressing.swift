import Foundation

@MainActor
public protocol WindowSuppressing: AnyObject, Sendable {
    @discardableResult
    func launch(app: ManagedApp) async throws -> any RunningAppRepresentable
}
