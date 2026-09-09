import Foundation

@MainActor
public protocol WindowSuppressing: AnyObject, Sendable {
    @discardableResult
    func launch(app: ManagedApp) async throws -> any RunningAppRepresentable
    func cancel(processIdentifier: pid_t)
    func cancelAll()
}

extension WindowSuppressing {
    public func cancel(processIdentifier: pid_t) {}
    public func cancelAll() {}
}
