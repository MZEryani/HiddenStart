import Foundation

@MainActor
public protocol ApplicationPickerSelecting: AnyObject {
    func pickApplicationURL() async -> URL?
}
