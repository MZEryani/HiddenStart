#if canImport(Testing)
import Testing
#endif
#if canImport(XCTest)
import XCTest
#endif
import AppKit
@testable import HiddenStart

@MainActor
final class MockPopover: PopoverPresenting {
    var isShown: Bool = false
    private(set) var showCalledCount = 0
    private(set) var closeCalledCount = 0

    func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        showCalledCount += 1
        isShown = true
    }

    func close() {
        closeCalledCount += 1
        isShown = false
    }
}

@MainActor
struct StatusItemControllerTestFixture {
    let mockPopover: MockPopover
    let viewModel: StatusViewModel
    let controller: StatusItemController
    let dummyView: NSView

    init() {
        self.mockPopover = MockPopover()
        self.viewModel = StatusViewModel()
        self.controller = StatusItemController(
            viewModel: viewModel,
            popover: mockPopover,
            statusBar: nil
        )
        self.dummyView = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    }
}

#if canImport(Testing)
@Suite("StatusItemController Tests")
@MainActor
struct StatusItemControllerTests {
    @Test("Toggle popover opens when currently closed")
    func togglePopoverOpensWhenClosed() {
        let fixture = StatusItemControllerTestFixture()

        #expect(!fixture.mockPopover.isShown)
        fixture.controller.togglePopover(from: fixture.dummyView)

        #expect(fixture.mockPopover.isShown)
        #expect(fixture.mockPopover.showCalledCount == 1)
        #expect(fixture.mockPopover.closeCalledCount == 0)
    }

    @Test("Toggle popover closes when currently open")
    func togglePopoverClosesWhenOpen() {
        let fixture = StatusItemControllerTestFixture()

        // Open first
        fixture.controller.togglePopover(from: fixture.dummyView)
        #expect(fixture.mockPopover.isShown)

        // Toggle again to close
        fixture.controller.togglePopover(from: fixture.dummyView)
        #expect(!fixture.mockPopover.isShown)
        #expect(fixture.mockPopover.showCalledCount == 1)
        #expect(fixture.mockPopover.closeCalledCount == 1)
    }

    @Test("Close popover directly closes popover")
    func closePopoverDirectly() {
        let fixture = StatusItemControllerTestFixture()
        fixture.controller.togglePopover(from: fixture.dummyView)
        #expect(fixture.mockPopover.isShown)

        fixture.controller.closePopover()
        #expect(!fixture.mockPopover.isShown)
        #expect(fixture.mockPopover.closeCalledCount == 1)
    }
}
#endif

#if canImport(XCTest)
@MainActor
final class StatusItemControllerXCTest: XCTestCase {
    func testTogglePopoverOpensWhenClosed() {
        let fixture = StatusItemControllerTestFixture()

        XCTAssertFalse(fixture.mockPopover.isShown)
        fixture.controller.togglePopover(from: fixture.dummyView)

        XCTAssertTrue(fixture.mockPopover.isShown)
        XCTAssertEqual(fixture.mockPopover.showCalledCount, 1)
        XCTAssertEqual(fixture.mockPopover.closeCalledCount, 0)
    }

    func testTogglePopoverClosesWhenOpen() {
        let fixture = StatusItemControllerTestFixture()

        fixture.controller.togglePopover(from: fixture.dummyView)
        XCTAssertTrue(fixture.mockPopover.isShown)

        fixture.controller.togglePopover(from: fixture.dummyView)
        XCTAssertFalse(fixture.mockPopover.isShown)
        XCTAssertEqual(fixture.mockPopover.showCalledCount, 1)
        XCTAssertEqual(fixture.mockPopover.closeCalledCount, 1)
    }

    func testClosePopoverDirectly() {
        let fixture = StatusItemControllerTestFixture()
        fixture.controller.togglePopover(from: fixture.dummyView)
        XCTAssertTrue(fixture.mockPopover.isShown)

        fixture.controller.closePopover()
        XCTAssertFalse(fixture.mockPopover.isShown)
        XCTAssertEqual(fixture.mockPopover.closeCalledCount, 1)
    }
}
#endif
