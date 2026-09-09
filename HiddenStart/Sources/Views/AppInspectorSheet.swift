import SwiftUI
import AppKit

public struct AppInspectorSheet: View {
    @State private var delaySeconds: Double
    @State private var waitForInternet: Bool
    @State private var launchHidden: Bool
    @State private var customArguments: String

    public let app: ManagedApp
    public let icon: NSImage
    public let onSave: (ManagedApp) -> Void
    public let onCancel: () -> Void
    public let onTestLaunch: (ManagedApp) -> Void

    public init(
        app: ManagedApp,
        icon: NSImage,
        onSave: @escaping (ManagedApp) -> Void,
        onCancel: @escaping () -> Void,
        onTestLaunch: @escaping (ManagedApp) -> Void
    ) {
        self.app = app
        self.icon = icon
        self.onSave = onSave
        self.onCancel = onCancel
        self.onTestLaunch = onTestLaunch

        _delaySeconds = State(initialValue: Double(app.delaySeconds))
        _waitForInternet = State(initialValue: app.waitForInternet)
        _launchHidden = State(initialValue: app.launchHidden)
        _customArguments = State(initialValue: app.customArguments)
    }

    private var currentConfiguredApp: ManagedApp {
        var updated = app
        updated.delaySeconds = Int(delaySeconds)
        updated.waitForInternet = waitForInternet
        updated.launchHidden = launchHidden
        updated.customArguments = customArguments
        return updated
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            Divider()

            delaySection

            Divider()

            optionsSection

            Divider()

            argumentsSection

            Spacer(minLength: 8)

            Divider()

            footerButtons
        }
        .padding(18)
        .frame(width: 380)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                Text(app.bundlePath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var delaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Launch Delay")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(delaySeconds))s")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $delaySeconds, in: 0...180, step: 1) {
                Text("Launch Delay")
            } minimumValueLabel: {
                Text("0s").font(.caption2).foregroundColor(.secondary)
            } maximumValueLabel: {
                Text("180s").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $waitForInternet) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Network Gate")
                        .font(.subheadline)
                    Text("Delays launch until active network connectivity is verified.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $launchHidden) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch Hidden")
                        .font(.subheadline)
                    Text("Suppresses windows and focus-stealing on launch.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private var argumentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom Arguments")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("e.g. --start-minimized or -silent", text: $customArguments)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var footerButtons: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                onSave(currentConfiguredApp)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}
