import Foundation
@testable import HiddenStart

@MainActor
public final class MockApplicationPicker: ApplicationPickerSelecting {
    public var appToReturn: ManagedApp?
    public var pickApplicationCallCount = 0

    public init(appToReturn: ManagedApp? = nil) {
        self.appToReturn = appToReturn
    }

    public func pickApplication() async -> ManagedApp? {
        pickApplicationCallCount += 1
        return appToReturn
    }
}
