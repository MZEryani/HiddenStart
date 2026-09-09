import Foundation

@MainActor
public protocol ApplicationPickerSelecting: AnyObject {
    func pickApplication() async -> ManagedApp?
}
