#if canImport(Testing)
import Testing
#endif
#if canImport(XCTest)
import XCTest
#endif
import Foundation
@testable import HiddenStart

#if canImport(Testing)
@Suite("StatusPresenter Tests")
struct StatusPresenterTests {
    @Test("NetworkStatusLevel returns expected display text")
    func networkStatusLevelDisplayText() {
        #expect(NetworkStatusLevel.connected.displayText == "Network connected")
        #expect(NetworkStatusLevel.waiting.displayText == "Waiting for network...")
        #expect(NetworkStatusLevel.skippedOffline.displayText == "Skipped (Offline)")
    }

    @Test("StatusDisplay initializes with provided properties and derives networkStatusText")
    func statusDisplayProperties() {
        let display = StatusDisplay(
            message: "All systems go",
            networkStatusLevel: .connected,
            remainingDelays: [:]
        )
        #expect(display.message == "All systems go")
        #expect(display.networkStatusLevel == .connected)
        #expect(display.networkStatusText == "Network connected")
        #expect(display.remainingDelays.isEmpty)
    }

    @Test("StatusPresenter default initialization sets Ready message and connected level")
    func defaultInitialization() {
        let presenter = StatusPresenter()
        #expect(presenter.currentDisplay.message == "Ready")
        #expect(presenter.currentDisplay.networkStatusLevel == .connected)
        #expect(presenter.currentDisplay.networkStatusText == "Network connected")
        #expect(presenter.currentDisplay.remainingDelays.isEmpty)
    }

    @Test("StatusPresenter custom initialization preserves custom message and level")
    func customInitialization() {
        let presenter = StatusPresenter(initialMessage: "Starting up...", initialLevel: .waiting)
        #expect(presenter.currentDisplay.message == "Starting up...")
        #expect(presenter.currentDisplay.networkStatusLevel == .waiting)
        #expect(presenter.currentDisplay.networkStatusText == "Waiting for network...")
    }

    @Test("deriveNetworkStatusLevel derives level from StartupRunState")
    func deriveNetworkStatusLevelFromState() {
        // Connected
        let connectedState = StartupRunState(isNetworkConnected: true)
        #expect(StatusPresenter.deriveNetworkStatusLevel(from: connectedState) == .connected)

        // Waiting (offline, not deferredRetry, no skipped apps)
        let waitingState = StartupRunState(isNetworkConnected: false)
        #expect(StatusPresenter.deriveNetworkStatusLevel(from: waitingState) == .waiting)

        // Skipped offline in deferredRetry
        let deferredState = StartupRunState(phase: .deferredRetry, isNetworkConnected: false)
        #expect(StatusPresenter.deriveNetworkStatusLevel(from: deferredState) == .skippedOffline)

        // Skipped offline with skipped apps
        let skippedState = StartupRunState(phase: .idle, isNetworkConnected: true, skippedAppIds: [UUID()])
        #expect(StatusPresenter.deriveNetworkStatusLevel(from: skippedState) == .skippedOffline)
    }

    @Test("deriveCoordinatorMessage formats single app launch delay")
    func deriveCoordinatorMessageSingleAppDelay() {
        let id = UUID()
        let app = ManagedApp(id: id, name: "Discord", bundlePath: "/Applications/Discord.app")
        let state = StartupRunState(phase: .running, remainingDelays: [id: 4])

        let message = StatusPresenter.deriveCoordinatorMessage(from: state, apps: [app])
        #expect(message == "Discord in 4s")
    }

    @Test("deriveCoordinatorMessage sorts multiple remaining delays ascending")
    func deriveCoordinatorMessageMultipleDelaysSorted() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let app1 = ManagedApp(id: id1, name: "Discord", bundlePath: "/Applications/Discord.app")
        let app2 = ManagedApp(id: id2, name: "Slack", bundlePath: "/Applications/Slack.app")
        let app3 = ManagedApp(id: id3, name: "Spotify", bundlePath: "/Applications/Spotify.app")

        let state = StartupRunState(
            phase: .running,
            remainingDelays: [
                id1: 15,
                id2: 3,
                id3: 8
            ]
        )

        let message = StatusPresenter.deriveCoordinatorMessage(from: state, apps: [app1, app2, app3])
        #expect(message == "Slack in 3s, Spotify in 8s, Discord in 15s")
    }

    @Test("deriveCoordinatorMessage ignores delays for apps not present in managed apps list")
    func deriveCoordinatorMessageMissingAppInDelays() {
        let knownId = UUID()
        let unknownId = UUID()
        let knownApp = ManagedApp(id: knownId, name: "Discord", bundlePath: "/Applications/Discord.app")

        let state = StartupRunState(
            phase: .running,
            remainingDelays: [knownId: 5, unknownId: 2]
        )

        let message = StatusPresenter.deriveCoordinatorMessage(from: state, apps: [knownApp])
        #expect(message == "Discord in 5s")
    }

    @Test("deriveCoordinatorMessage derives status across different phases")
    func deriveCoordinatorMessagePhases() {
        // Waiting for network
        let waitingState = StartupRunState(phase: .running, waitingForNetworkAppIds: [UUID()])
        #expect(StatusPresenter.deriveCoordinatorMessage(from: waitingState, apps: []) == "Waiting for network...")

        // Deferred retry
        let deferredState = StartupRunState(phase: .deferredRetry)
        #expect(StatusPresenter.deriveCoordinatorMessage(from: deferredState, apps: []) == "Skipped (Offline)")

        // Idle with skipped apps
        let idleSkippedState = StartupRunState(phase: .idle, skippedAppIds: [UUID()])
        #expect(StatusPresenter.deriveCoordinatorMessage(from: idleSkippedState, apps: []) == "Skipped (Offline)")

        // Running without delays
        let runningState = StartupRunState(phase: .running)
        #expect(StatusPresenter.deriveCoordinatorMessage(from: runningState, apps: []) == "Launching...")

        // Idle
        let idleState = StartupRunState(phase: .idle)
        #expect(StatusPresenter.deriveCoordinatorMessage(from: idleState, apps: []) == "Ready")
    }

    @Test("setActionMessage updates current display message and returns updated display")
    func setActionMessageUpdatesDisplay() {
        var presenter = StatusPresenter()
        let display = presenter.setActionMessage("Added Discord")

        #expect(display.message == "Added Discord")
        #expect(presenter.currentDisplay.message == "Added Discord")
        #expect(presenter.currentDisplay.networkStatusLevel == .connected)
    }

    @Test("Action message is preserved across idle pulses")
    func actionMessagePreservedAcrossIdlePulses() {
        var presenter = StatusPresenter()
        presenter.setActionMessage("Updated Spotify")

        let idleState = StartupRunState(phase: .idle, isNetworkConnected: true)
        let updatedDisplay = presenter.update(state: idleState, apps: [])

        #expect(updatedDisplay.message == "Updated Spotify")
        #expect(presenter.currentDisplay.message == "Updated Spotify")
    }

    @Test("Active startup run clears action message and takes coordinator precedence")
    func activeStartupRunClearsActionMessage() {
        var presenter = StatusPresenter()
        presenter.setActionMessage("Removed Slack")

        let runningState = StartupRunState(phase: .running, isNetworkConnected: true)
        let updatedDisplay = presenter.update(state: runningState, apps: [])

        #expect(updatedDisplay.message == "Launching...")
        #expect(presenter.currentDisplay.message == "Launching...")
    }

    @Test("Completing a startup run transitions from running back to Ready")
    func startupRunCompletionTransitionsToReady() {
        var presenter = StatusPresenter()
        let runningState = StartupRunState(phase: .running, isNetworkConnected: true)
        _ = presenter.update(state: runningState, apps: [])
        #expect(presenter.currentDisplay.message == "Launching...")

        let idleState = StartupRunState(phase: .idle, isNetworkConnected: true)
        let completedDisplay = presenter.update(state: idleState, apps: [])

        #expect(completedDisplay.message == "Ready")
        #expect(presenter.currentDisplay.message == "Ready")
    }

    @Test("Startup Run completion clears action message if one was set during execution")
    func runCompletionClearsActionMessage() {
        var presenter = StatusPresenter()
        let runningState = StartupRunState(phase: .running, isNetworkConnected: true)
        _ = presenter.update(state: runningState, apps: [])

        // User performed an action mid-run
        _ = presenter.setActionMessage("Test launch triggered for Discord")
        #expect(presenter.currentDisplay.message == "Test launch triggered for Discord")

        // Run completes
        let idleState = StartupRunState(phase: .idle, isNetworkConnected: true)
        let completedDisplay = presenter.update(state: idleState, apps: [])

        #expect(completedDisplay.message == "Ready")
        #expect(presenter.currentDisplay.message == "Ready")
    }

    @Test("update updates remaining delays and network status level")
    func updateUpdatesDelaysAndNetworkStatusLevel() {
        var presenter = StatusPresenter()
        let id = UUID()
        let app = ManagedApp(id: id, name: "Discord", bundlePath: "/Applications/Discord.app")

        let state = StartupRunState(
            phase: .running,
            remainingDelays: [id: 7],
            isNetworkConnected: false
        )

        let display = presenter.update(state: state, apps: [app])

        #expect(display.message == "Discord in 7s")
        #expect(display.remainingDelays[id] == 7)
        #expect(display.networkStatusLevel == .waiting)
        #expect(display.networkStatusText == "Waiting for network...")
    }
}
#endif

