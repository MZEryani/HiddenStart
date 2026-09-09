import SwiftUI

public struct PopoverContentView: View {
    @ObservedObject public var viewModel: StatusViewModel
    @State private var editingApp: ManagedApp?

    public init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            diagnosticBannerView

            statusView

            Divider()

            managedAppsSection

            Divider()

            footerView
        }
        .padding(16)
        .frame(width: 380)
        .sheet(item: $editingApp) { app in
            AppInspectorSheet(
                app: app,
                icon: viewModel.icon(for: app),
                onSave: { updatedApp in
                    viewModel.updateApplication(updatedApp)
                    editingApp = nil
                },
                onCancel: {
                    editingApp = nil
                },
                onTestLaunch: { configuredApp in
                    Task {
                        await viewModel.testLaunch(app: configuredApp)
                    }
                }
            )
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .imageScale(.medium)
                .foregroundColor(.accentColor)
            Text(viewModel.title)
                .font(.headline)
            Spacer()
            Toggle("Launch HiddenStart at Login", isOn: Binding(
                get: { viewModel.isAutoStartEnabled },
                set: { _ in viewModel.toggleAutoStart() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
        }
    }

    @ViewBuilder
    private var diagnosticBannerView: some View {
        if viewModel.autoStartRequiresApproval {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .imageScale(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Login Item Requires Approval")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Enable HiddenStart in System Settings > Login Items.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Open System Settings") {
                    viewModel.openSystemSettingsLoginItems()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.yellow.opacity(0.12))
            .cornerRadius(6)
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.networkStatus.isEmpty {
                    Text(viewModel.networkStatus)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(networkStatusColor)
                }
            }
            Text(viewModel.statusMessage)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var networkStatusColor: Color {
        switch viewModel.networkStatus {
        case "Network connected":
            return .green
        case "Skipped (Offline)":
            return .orange
        default:
            return .secondary
        }
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
        let isMissing = viewModel.isAppMissing(app)

        return HStack(spacing: 10) {
            Image(nsImage: viewModel.icon(for: app))
                .resizable()
                .frame(width: 28, height: 28)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isMissing ? .secondary : (app.isEnabled ? .primary : .secondary))

                    if isMissing {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("App Not Found")
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(4)
                    } else if let remainingDelay = viewModel.remainingDelays[app.id] {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                            Text("\(remainingDelay)s")
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                    } else if !app.isEnabled {
                        Text("(Disabled)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(app.configurationSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Edit") {
                editingApp = app
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

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
        .contextMenu {
            Button("Edit Settings...") {
                editingApp = app
            }
            Button("Test Launch") {
                Task {
                    await viewModel.testLaunch(app: app)
                }
            }
            Divider()
            Button(role: .destructive) {
                viewModel.removeApplication(withId: app.id)
            } label: {
                Label("Remove Application", systemImage: "trash")
            }
        }
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
