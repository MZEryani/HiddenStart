import Testing
import Foundation
@testable import HiddenStart

@Suite("ApplicationPicker Tests")
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
}
