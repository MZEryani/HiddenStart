import Foundation

public enum AppPreset {
    public static func makeManagedApp(
        name: String,
        bundlePath: String,
        bundleIdentifier: String?,
        delaySeconds: Int = 10,
        sortOrder: Int = 0
    ) -> ManagedApp {
        var customArguments = ""
        var waitForInternet = true
        var launchHidden = true
        var resolvedDelay = delaySeconds

        switch bundleIdentifier?.lowercased() {
        case "com.hammerandchisel.discord":
            customArguments = "--start-minimized"
            waitForInternet = true
            launchHidden = true
        case "com.valvesoftware.steam":
            customArguments = "-silent"
            waitForInternet = true
            launchHidden = true
        case "com.spotify.client":
            customArguments = ""
            waitForInternet = false
            launchHidden = true
            resolvedDelay = min(resolvedDelay, 5)
        default:
            break
        }

        return ManagedApp(
            name: name,
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            delaySeconds: resolvedDelay,
            waitForInternet: waitForInternet,
            launchHidden: launchHidden,
            isEnabled: true,
            customArguments: customArguments,
            sortOrder: sortOrder
        )
    }
}
