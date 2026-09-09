import Foundation

public struct ManagedApp: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var bundlePath: String
    public var bundleIdentifier: String?
    public var delaySeconds: Int
    public var waitForInternet: Bool
    public var launchHidden: Bool
    public var isEnabled: Bool
    public var customArguments: String
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        bundlePath: String,
        bundleIdentifier: String? = nil,
        delaySeconds: Int = 10,
        waitForInternet: Bool = true,
        launchHidden: Bool = true,
        isEnabled: Bool = true,
        customArguments: String = "",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.delaySeconds = delaySeconds
        self.waitForInternet = waitForInternet
        self.launchHidden = launchHidden
        self.isEnabled = isEnabled
        self.customArguments = customArguments
        self.sortOrder = sortOrder
    }

    public var bundleURL: URL {
        URL(fileURLWithPath: bundlePath)
    }

    public var argumentsArray: [String] {
        customArguments
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bundlePath, bundleIdentifier, delaySeconds
        case waitForInternet, launchHidden, isEnabled, customArguments, sortOrder
        // Legacy keys for migration support
        case path, arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)

        if let path = try container.decodeIfPresent(String.self, forKey: .bundlePath) {
            self.bundlePath = path
        } else if let legacyPath = try container.decodeIfPresent(String.self, forKey: .path) {
            self.bundlePath = legacyPath
        } else {
            self.bundlePath = ""
        }

        self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        self.delaySeconds = try container.decodeIfPresent(Int.self, forKey: .delaySeconds) ?? 10
        self.waitForInternet = try container.decodeIfPresent(Bool.self, forKey: .waitForInternet) ?? true
        self.launchHidden = try container.decodeIfPresent(Bool.self, forKey: .launchHidden) ?? true
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        if let args = try container.decodeIfPresent(String.self, forKey: .customArguments) {
            self.customArguments = args
        } else if let legacyArgs = try container.decodeIfPresent(String.self, forKey: .arguments) {
            self.customArguments = legacyArgs
        } else {
            self.customArguments = ""
        }

        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bundlePath, forKey: .bundlePath)
        try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(delaySeconds, forKey: .delaySeconds)
        try container.encode(waitForInternet, forKey: .waitForInternet)
        try container.encode(launchHidden, forKey: .launchHidden)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(customArguments, forKey: .customArguments)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}
