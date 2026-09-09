import Foundation

public struct PresetConfiguration: Sendable {
    public let customArguments: String
    public let waitForInternet: Bool
    public let launchHidden: Bool
    public let maxDelaySeconds: Int?
}

public enum AppPreset {
    private static let discordPreset = PresetConfiguration(
        customArguments: "",
        waitForInternet: true,
        launchHidden: true,
        maxDelaySeconds: nil
    )

    public static let knownPresets: [String: PresetConfiguration] = [
        "com.hammerandchisel.discord": discordPreset,
        "com.hnc.discord": discordPreset,
        "com.valvesoftware.steam": PresetConfiguration(
            customArguments: "-silent",
            waitForInternet: true,
            launchHidden: true,
            maxDelaySeconds: nil
        ),
        "com.spotify.client": PresetConfiguration(
            customArguments: "",
            waitForInternet: false,
            launchHidden: true,
            maxDelaySeconds: 5
        )
    ]

    public static func makeManagedApp(
        name: String,
        bundlePath: String,
        bundleIdentifier: String?,
        delaySeconds: Int = 10,
        sortOrder: Int = 0
    ) -> ManagedApp {
        let preset = bundleIdentifier.flatMap { knownPresets[$0.lowercased()] }
        var resolvedDelay = delaySeconds
        if let maxDelay = preset?.maxDelaySeconds {
            resolvedDelay = min(resolvedDelay, maxDelay)
        }

        return ManagedApp(
            name: name,
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            delaySeconds: resolvedDelay,
            waitForInternet: preset?.waitForInternet ?? true,
            launchHidden: preset?.launchHidden ?? true,
            isEnabled: true,
            customArguments: preset?.customArguments ?? "",
            sortOrder: sortOrder
        )
    }

    public static func defaultArguments(forBundleId bundleId: String?) -> String? {
        guard let bundleId = bundleId?.lowercased(),
              let args = knownPresets[bundleId]?.customArguments,
              !args.isEmpty else {
            return nil
        }
        return args
    }
}
