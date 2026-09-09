import Foundation
import Combine

@MainActor
public final class StatusViewModel: ObservableObject {
    public let title: String
    @Published public var statusMessage: String
    private let terminator: AppTerminating

    public init(
        title: String = "HiddenStart",
        statusMessage: String = "Ready",
        terminator: AppTerminating = SystemAppTerminator()
    ) {
        self.title = title
        self.statusMessage = statusMessage
        self.terminator = terminator
    }

    public func quit() {
        terminator.terminate()
    }
}
