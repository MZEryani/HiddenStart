import Foundation

@MainActor
public protocol FocusGuarding: AnyObject, Sendable {
    var isGuarding: Bool { get }
    func startGuarding(app: any RunningAppRepresentable)
    func cancel()
}
