import Foundation

@MainActor
public protocol FocusGuarding: AnyObject, Sendable {
    var isGuarding: Bool { get }
    func isGuarding(processIdentifier: pid_t) -> Bool
    func startGuarding(app: any RunningAppRepresentable)
    func cancel(processIdentifier: pid_t)
    func cancel()
}
