#if canImport(Testing)
import Testing
#endif
#if canImport(XCTest)
import XCTest
#endif
import AppKit
import SwiftUI
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

    @Test("Popover content view add application action dismisses popover")
    func addApplicationActionDismissesPopover() {
        let fixture = StatusItemControllerTestFixture()
        fixture.controller.togglePopover(from: fixture.dummyView)
        #expect(fixture.mockPopover.isShown)

        let contentView = PopoverContentView(viewModel: fixture.viewModel) {
            fixture.controller.closePopover()
        }

        contentView.onAddApplication?()
        #expect(!fixture.mockPopover.isShown)
        #expect(fixture.mockPopover.closeCalledCount == 1)
    }

    @Test("Standard StatusItemController configures popover content with dismissal callback")
    func standardStatusItemControllerWiresDismissalCallback() {
        let viewModel = StatusViewModel()
        let controller = StatusItemController(viewModel: viewModel, popover: nil, statusBar: nil)
        guard let popover = controller.popover as? NSPopover,
              let hosting = popover.contentViewController as? NSHostingController<PopoverContentView> else {
            Issue.record("Expected NSPopover with NSHostingController<PopoverContentView>")
            return
        }

        #expect(hosting.rootView.onAddApplication != nil)
    }

    @Test("End-to-end boot launch flow executes startup run and heals apps")
    func testEndToEndBootLaunchFlow() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("apps.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let movedApp = ManagedApp(
            name: "Slack",
            bundlePath: "/Applications/OldSlack.app",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            delaySeconds: 0,
            waitForInternet: false,
            isEnabled: true
        )
        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.applicationURLs["com.tinyspeck.slackmacgap"] = URL(fileURLWithPath: "/Applications/NewSlack.app")

        let store = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in path == "/Applications/NewSlack.app" }
        )
        try store.addDirectlyForTesting(movedApp)

        let suppressor = MockWindowSuppressor()
        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: suppressor,
            networkMonitor: MockNetworkMonitor(isConnected: true),
            sleep: { _ in }
        )

        let viewModel = StatusViewModel(
            managedAppStore: store,
            startupRunCoordinator: coordinator,
            workspaceManager: mockWorkspace
        )



        let controller = StatusItemController(
            viewModel: viewModel,
            popover: MockPopover(),
            statusBar: nil
        )

        controller.viewModel.startStartupRun()
        try await Task.sleep(for: .milliseconds(30))

        #expect(suppressor.launchedApps.count == 1)
        #expect(suppressor.launchedApps.first?.bundlePath == "/Applications/NewSlack.app")
        #expect(viewModel.isAppMissing(movedApp) == false)
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

    func testAddApplicationActionDismissesPopover() {
        let fixture = StatusItemControllerTestFixture()
        fixture.controller.togglePopover(from: fixture.dummyView)
        XCTAssertTrue(fixture.mockPopover.isShown)

        let contentView = PopoverContentView(viewModel: fixture.viewModel) {
            fixture.controller.closePopover()
        }

        contentView.onAddApplication?()
        XCTAssertFalse(fixture.mockPopover.isShown)
        XCTAssertEqual(fixture.mockPopover.closeCalledCount, 1)
    }
}
#endif
