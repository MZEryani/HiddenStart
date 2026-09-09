import Foundation
@testable import HiddenStart

@MainActor
public final class MockRunningApp: RunningAppRepresentable {
    public var processIdentifier: pid_t
    public var bundleIdentifier: String?
    public var bundleURL: URL?
    public var isFinishedLaunching: Bool
    public var hideCallCount: Int = 0
    public var hideReturnValue: Bool = true

    public init(
        processIdentifier: pid_t = 1234,
        bundleIdentifier: String? = "com.test.app",
        bundleURL: URL? = nil,
        isFinishedLaunching: Bool = true
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.isFinishedLaunching = isFinishedLaunching
    }

    @discardableResult
    public func hide() -> Bool {
        hideCallCount += 1
        return hideReturnValue
    }
}
