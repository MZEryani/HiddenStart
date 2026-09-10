import Testing
import Foundation
import AppKit
import UniformTypeIdentifiers
@testable import HiddenStart

@Suite("ApplicationPicker Tests")
@MainActor
struct ApplicationPickerTests {

    @Test("BundleAppResolver extracts bundle info and applies presets")
    func testBundleAppResolver() {
        // System Applications/Calculator.app or Safari.app usually exists on macOS
        let safariURL = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
        let urlToUse: URL
        if FileManager.default.fileExists(atPath: safariURL.path) {
            urlToUse = safariURL
        } else {
            urlToUse = URL(fileURLWithPath: "/Applications/Safari.app")
        }

        if FileManager.default.fileExists(atPath: urlToUse.path) {
            let app = BundleAppResolver.resolveApp(at: urlToUse)
            #expect(!app.name.isEmpty)
            #expect(app.bundlePath == urlToUse.path)
            #expect(app.bundleIdentifier?.contains("Safari") == true)
        }
    }

    @Test("BundleAppResolver creates preset for simulated app bundle")
    func testBundleAppResolverFallback() {
        let fakeURL = URL(fileURLWithPath: "/Applications/CustomTool.app")
        let app = BundleAppResolver.resolveApp(at: fakeURL)

        #expect(app.name == "CustomTool")
        #expect(app.bundlePath == "/Applications/CustomTool.app")
        #expect(app.customArguments == "")
        #expect(app.launchHidden == true)
        #expect(app.waitForInternet == true)
    }

    @Test("ApplicationPicker activates application and configures panel attributes before presenting")
    func testApplicationPickerConfiguresPanelAndActivates() async {
        var activationCallCount = 0
        var activatedBeforePresentation = false
        var configuredPanel: NSOpenPanel?

        let fakeAppURL = URL(fileURLWithPath: "/Applications/CustomTool.app")

        let picker = ApplicationPicker(
            appActivator: { ignoringOtherApps in
                #expect(ignoringOtherApps == true)
                activationCallCount += 1
            },
            panelFactory: {
                let panel = NSOpenPanel()
                configuredPanel = panel
                return panel
            },
            panelPresenter: { panel in
                if activationCallCount > 0 {
                    activatedBeforePresentation = true
                }
                return (.OK, fakeAppURL)
            }
        )

        let result = await picker.pickApplication()

        #expect(activationCallCount == 1)
        #expect(activatedBeforePresentation == true)
        #expect(result?.name == "CustomTool")
        #expect(result?.bundlePath == "/Applications/CustomTool.app")

        guard let panel = configuredPanel else {
            Issue.record("Panel was not created")
            return
        }

        #expect(panel.treatsFilePackagesAsDirectories == false)
        #expect(panel.canChooseDirectories == false)
        #expect(panel.canCreateDirectories == false)
        #expect(panel.allowsMultipleSelection == false)
        #expect(panel.showsHiddenFiles == false)
        #expect(panel.allowedContentTypes == [.applicationBundle])
        #expect(panel.directoryURL == URL(fileURLWithPath: "/Applications"))
        #expect(panel.title == "Select Application to Manage")
    }

    @Test("ApplicationPicker returns nil when panel is cancelled")
    func testApplicationPickerCancelled() async {
        var activationCallCount = 0

        let picker = ApplicationPicker(
            appActivator: { _ in
                activationCallCount += 1
            },
            panelPresenter: { _ in
                return (.cancel, nil)
            }
        )

        let result = await picker.pickApplication()

        #expect(activationCallCount == 1)
        #expect(result == nil)
    }
}
