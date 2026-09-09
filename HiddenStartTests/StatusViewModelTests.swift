#if canImport(Testing)
import Testing
#endif
#if canImport(XCTest)
import XCTest
#endif
@testable import HiddenStart

@MainActor
final class MockAppTerminator: AppTerminating {
    private(set) var terminateCalled = false

    func terminate() {
        terminateCalled = true
    }
}

#if canImport(Testing)
@Suite("StatusViewModel Tests")
@MainActor
struct StatusViewModelTests {
    @Test("Default initialization has expected title and status")
    func defaultInitialization() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(terminator: mockTerminator)

        #expect(viewModel.title == "HiddenStart")
        #expect(viewModel.statusMessage == "Ready")
    }

    @Test("Custom status message is preserved")
    func customStatusMessage() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(statusMessage: "3 apps queued", terminator: mockTerminator)

        #expect(viewModel.statusMessage == "3 apps queued")
    }

    @Test("Quit delegates to terminator")
    func quitDelegatesToTerminator() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(terminator: mockTerminator)

        #expect(!mockTerminator.terminateCalled)
        viewModel.quit()
        #expect(mockTerminator.terminateCalled)
    }
}
#endif

#if canImport(XCTest)
@MainActor
final class StatusViewModelXCTest: XCTestCase {
    func testDefaultInitialization() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(terminator: mockTerminator)

        XCTAssertEqual(viewModel.title, "HiddenStart")
        XCTAssertEqual(viewModel.statusMessage, "Ready")
    }

    func testCustomStatusMessage() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(statusMessage: "3 apps queued", terminator: mockTerminator)

        XCTAssertEqual(viewModel.statusMessage, "3 apps queued")
    }

    func testQuitDelegatesToTerminator() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(terminator: mockTerminator)

        XCTAssertFalse(mockTerminator.terminateCalled)
        viewModel.quit()
        XCTAssertTrue(mockTerminator.terminateCalled)
    }
}
#endif
