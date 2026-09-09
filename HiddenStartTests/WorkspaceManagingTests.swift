import Testing
import Foundation
import AppKit
@testable import HiddenStart

@Suite("WorkspaceManaging Tests")
struct WorkspaceManagingTests {

    @Test("Test launch configures OpenConfiguration with hides, activates=false, and split arguments")
    @MainActor
    func testTestLaunchConfiguration() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            customArguments: "--start-minimized --multi-instance"
        )

        let config = NSWorkspace.OpenConfiguration()
        config.hides = app.launchHidden
        config.activates = false
        let args = app.argumentsArray
        if !args.isEmpty {
            config.arguments = args
        }

        let runningApp = try await mockWorkspace.openApplication(at: app.bundleURL, configuration: config)

        #expect(mockWorkspace.openedURLs.count == 1)
        #expect(mockWorkspace.openedURLs.first == app.bundleURL)
        #expect(mockWorkspace.configurations.first?.hides == true)
        #expect(mockWorkspace.configurations.first?.activates == false)
        #expect(mockWorkspace.configurations.first?.arguments == ["--start-minimized", "--multi-instance"])
        #expect(runningApp.processIdentifier == 1234)
    }
}
