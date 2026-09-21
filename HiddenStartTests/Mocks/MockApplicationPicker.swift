import Foundation
@testable import HiddenStart

@MainActor
public final class MockApplicationPicker: ApplicationPickerSelecting {
    public var urlToReturn: URL?
    public var pickApplicationURLCallCount = 0

    public init(urlToReturn: URL? = nil) {
        self.urlToReturn = urlToReturn
    }

    public func pickApplicationURL() async -> URL? {
        pickApplicationURLCallCount += 1
        return urlToReturn
    }
}
