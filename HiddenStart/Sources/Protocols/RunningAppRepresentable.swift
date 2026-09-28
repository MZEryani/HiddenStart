import AppKit

@MainActor
public protocol RunningAppRepresentable: AnyObject, Sendable {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    var bundleURL: URL? { get }
    var isFinishedLaunching: Bool { get }
    @discardableResult func hide() -> Bool
}

#if compiler(>=6.0)
extension NSRunningApplication: @retroactive @unchecked Sendable, RunningAppRepresentable {}
#else
extension NSRunningApplication: @unchecked Sendable, RunningAppRepresentable {}
#endif
