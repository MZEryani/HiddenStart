import AppKit

@MainActor
public protocol RunningAppRepresentable: AnyObject, Sendable {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    var isFinishedLaunching: Bool { get }
    @discardableResult func hide() -> Bool
}

extension NSRunningApplication: RunningAppRepresentable {}
