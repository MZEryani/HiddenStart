import AppKit

@MainActor
public protocol AppTerminating: AnyObject {
    func terminate()
}

@MainActor
public final class SystemAppTerminator: AppTerminating {
    public init() {}

    public func terminate() {
        NSApplication.shared.terminate(nil)
    }
}
