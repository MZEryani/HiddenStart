import SwiftUI

public struct PopoverContentView: View {
    @ObservedObject public var viewModel: StatusViewModel

    public init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            statusView

            Divider()

            managedAppsSection

            Divider()

            footerView
        }
        .padding(16)
        .frame(width: 360)
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .imageScale(.medium)
                .foregroundColor(.accentColor)
            Text(viewModel.title)
                .font(.headline)
            Spacer()
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(viewModel.statusMessage)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var managedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGED APPLICATIONS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if viewModel.managedApps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No managed applications yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Click \"+ Add Application...\" below to add one.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.managedApps) { app in
                            managedAppRow(app)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func managedAppRow(_ app: ManagedApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: viewModel.icon(for: app))
                .resizable()
                .frame(width: 28, height: 28)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(app.isEnabled ? .primary : .secondary)

                    if !app.isEnabled {
                        Text("(Disabled)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(summaryText(for: app))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Test") {
                Task {
                    await viewModel.testLaunch(app: app)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Toggle("", isOn: Binding(
                get: { app.isEnabled },
                set: { _ in viewModel.toggleAppEnabled(withId: app.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func summaryText(for app: ManagedApp) -> String {
        var parts: [String] = []
        parts.append("Wait \(app.delaySeconds)s")
        if app.waitForInternet {
            parts.append("Network Gate")
        }
        if app.launchHidden {
            var hiddenPart = "Launch Hidden"
            if !app.customArguments.isEmpty {
                hiddenPart += " (\(app.customArguments))"
            }
            parts.append(hiddenPart)
        } else if !app.customArguments.isEmpty {
            parts.append(app.customArguments)
        }
        return parts.joined(separator: " • ")
    }

    private var footerView: some View {
        HStack {
            Button("+ Add Application...") {
                Task {
                    await viewModel.addApplication()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()

            Button(action: {
                viewModel.quit()
            }) {
                Text("Quit")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
