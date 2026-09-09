import Testing
import Foundation
@testable import HiddenStart

@Suite("ManagedApp Tests")
struct ManagedAppTests {

    @Test("ManagedApp encodes and decodes JSON correctly")
    func testEncodingAndDecoding() throws {
        let app = ManagedApp(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "TestApp",
            bundlePath: "/Applications/TestApp.app",
            bundleIdentifier: "com.example.testapp",
            delaySeconds: 15,
            waitForInternet: true,
            launchHidden: false,
            isEnabled: true,
            customArguments: "--debug",
            sortOrder: 1
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(app)

        let decoder = JSONDecoder()
        let decodedApp = try decoder.decode(ManagedApp.self, from: data)

        #expect(decodedApp == app)
        #expect(decodedApp.bundleURL == URL(fileURLWithPath: "/Applications/TestApp.app"))
        #expect(decodedApp.argumentsArray == ["--debug"])
    }

    @Test("AppPreset configures Discord with launchHidden and empty arguments")
    func testDiscordPreset() {
        let app = AppPreset.makeManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hammerandchisel.discord"
        )

        #expect(app.customArguments == "")
        #expect(app.waitForInternet == true)
        #expect(app.launchHidden == true)
    }

    @Test("AppPreset configures Steam with -silent")
    func testSteamPreset() {
        let app = AppPreset.makeManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            bundleIdentifier: "com.valvesoftware.steam"
        )

        #expect(app.customArguments == "-silent")
        #expect(app.waitForInternet == true)
        #expect(app.launchHidden == true)
    }

    @Test("AppPreset configures standard app without custom arguments")
    func testStandardPreset() {
        let app = AppPreset.makeManagedApp(
            name: "Notes",
            bundlePath: "/System/Applications/Notes.app",
            bundleIdentifier: "com.apple.Notes"
        )

        #expect(app.customArguments == "")
        #expect(app.delaySeconds == 10)
        #expect(app.waitForInternet == true)
        #expect(app.launchHidden == true)
    }
}
