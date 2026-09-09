import Testing
import Foundation
import AppKit
@testable import HiddenStart

@Suite("FocusGuard Tests")
@MainActor
struct FocusGuardTests {

    @Test("Guarded app activation triggers hide()")
    func guardedAppActivationTriggersHide() async {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in try await Task.sleep(for: .seconds(100)) } // don't expire during test
        )
        let guardedApp = MockRunningApp(processIdentifier: 4321)

        guardInstance.startGuarding(app: guardedApp)
        #expect(guardInstance.isGuarding)
        #expect(guardedApp.hideCallCount == 0)

        // Post activation notification for guarded app
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: guardedApp]
        )

        #expect(guardedApp.hideCallCount == 1)
        guardInstance.cancel()
        #expect(!guardInstance.isGuarding)
    }

    @Test("Unrelated app activation does not trigger hide()")
    func unrelatedAppActivationDoesNotTriggerHide() async {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let guardedApp = MockRunningApp(processIdentifier: 4321)
        let otherApp = MockRunningApp(processIdentifier: 9999)

        guardInstance.startGuarding(app: guardedApp)

        // Post activation for other app
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: otherApp]
        )

        #expect(guardedApp.hideCallCount == 0)
        guardInstance.cancel()
    }

    @Test("Grace period expiration cleanly stops guarding and unsubscribes")
    func gracePeriodExpirationStopsGuarding() async throws {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .milliseconds(10),
            sleep: { _ in
                // Immediate sleep completion for testing
            }
        )
        let guardedApp = MockRunningApp(processIdentifier: 4321)

        guardInstance.startGuarding(app: guardedApp)
        // Yield to allow Task to execute
        try await Task.sleep(for: .milliseconds(50))

        #expect(!guardInstance.isGuarding)

        // Notification posted after expiration should NOT invoke hide
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: guardedApp]
        )
        #expect(guardedApp.hideCallCount == 0)
    }

    @Test("Explicit cancel removes observer immediately")
    func explicitCancelRemovesObserver() {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let guardedApp = MockRunningApp(processIdentifier: 4321)

        guardInstance.startGuarding(app: guardedApp)
        #expect(guardInstance.isGuarding)

        guardInstance.cancel()
        #expect(!guardInstance.isGuarding)

        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: guardedApp]
        )
        #expect(guardedApp.hideCallCount == 0)
    }

    @Test("Concurrent multi-process guarding tracks multiple apps simultaneously without collision")
    func concurrentMultiProcessGuarding() {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let app1 = MockRunningApp(processIdentifier: 1001)
        let app2 = MockRunningApp(processIdentifier: 1002)

        guardInstance.startGuarding(app: app1)
        guardInstance.startGuarding(app: app2)

        #expect(guardInstance.isGuarding)
        #expect(guardInstance.isGuarding(processIdentifier: 1001))
        #expect(guardInstance.isGuarding(processIdentifier: 1002))

        // Activate app1
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app1]
        )
        #expect(app1.hideCallCount == 1)
        #expect(app2.hideCallCount == 0)

        // Unhide app2
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app2]
        )
        #expect(app1.hideCallCount == 1)
        #expect(app2.hideCallCount == 1)

        #expect(guardInstance.isGuarding(processIdentifier: 1001))
        #expect(guardInstance.isGuarding(processIdentifier: 1002))
    }

    @Test("Unhide notification triggers hide() for guarded app")
    func unhideNotificationTriggersHide() {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let app = MockRunningApp(processIdentifier: 2002)
        guardInstance.startGuarding(app: app)

        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 1)
    }

    @Test("Two-strike threshold disarms process after 2 suppression actions")
    func twoStrikeThresholdDisarms() {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            maxSuppressionStrikes: 2,
            debounceInterval: 0,
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let app = MockRunningApp(processIdentifier: 3003)
        guardInstance.startGuarding(app: app)

        // Strike 1: updater window activation
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 1)
        #expect(guardInstance.isGuarding(processIdentifier: 3003))
        #expect(guardInstance.isGuarding)

        // Strike 2: main window unhide
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 2)
        // Disarmed after 2 strikes
        #expect(!guardInstance.isGuarding(processIdentifier: 3003))
        #expect(!guardInstance.isGuarding)

        // Strike 3 attempt (e.g. user intentional interaction): should NOT call hide
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 2)
    }

    @Test("Paired didActivate and didUnhide notifications within debounce window coalesce to single strike")
    func pairedNotificationsCoalesceToSingleStrike() {
        let notificationCenter = NotificationCenter()
        var mockTime = Date()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            maxSuppressionStrikes: 2,
            debounceInterval: 0.3,
            currentTime: { mockTime },
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let app = MockRunningApp(processIdentifier: 3004)
        guardInstance.startGuarding(app: app)

        // Event 1: didActivate
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 1)
        #expect(guardInstance.isGuarding(processIdentifier: 3004))

        // Event 2: didUnhide 10ms later (within 300ms debounce window)
        mockTime = mockTime.addingTimeInterval(0.01)
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        // hide() is called again for safety, but strike is NOT incremented
        #expect(app.hideCallCount == 2)
        #expect(guardInstance.isGuarding(processIdentifier: 3004))

        // Event 3: Subsequent activation after debounce window (0.5s later) -> Strike 2
        mockTime = mockTime.addingTimeInterval(0.5)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 3)
        // Disarmed after 2 distinct suppression actions
        #expect(!guardInstance.isGuarding(processIdentifier: 3004))
    }

    @Test("Multi-notification Electron launch sequence is suppressed without premature disarming")
    func multiNotificationElectronLaunchSuppressed() {
        let notificationCenter = NotificationCenter()
        var mockTime = Date()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            maxSuppressionStrikes: 3,
            debounceInterval: 0.3,
            currentTime: { mockTime },
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let app = MockRunningApp(processIdentifier: 3005)
        guardInstance.startGuarding(app: app)

        // 1. Initial process launch handshake (paired didActivate + didUnhide within 10ms)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        mockTime = mockTime.addingTimeInterval(0.01)
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 2)
        // Guard must NOT be disarmed by launch handshake!
        #expect(guardInstance.isGuarding(processIdentifier: 3005))

        // 2. Asynchronous Electron window rendering 0.8s later (paired didActivate + didUnhide)
        mockTime = mockTime.addingTimeInterval(0.8)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        mockTime = mockTime.addingTimeInterval(0.01)
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 4)
        // Still guarding after window suppression
        #expect(guardInstance.isGuarding(processIdentifier: 3005))

        // 3. User intentionally clicks Dock icon 2s later -> Strike 3 disarms guard
        mockTime = mockTime.addingTimeInterval(2.0)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
        #expect(app.hideCallCount == 5)
        #expect(!guardInstance.isGuarding(processIdentifier: 3005))
    }

    @Test("Targeted cancellation cancels specific process without affecting other guarded processes")
    func targetedCancellation() {
        let notificationCenter = NotificationCenter()
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )
        let app1 = MockRunningApp(processIdentifier: 4001)
        let app2 = MockRunningApp(processIdentifier: 4002)

        guardInstance.startGuarding(app: app1)
        guardInstance.startGuarding(app: app2)

        #expect(guardInstance.isGuarding(processIdentifier: 4001))
        #expect(guardInstance.isGuarding(processIdentifier: 4002))

        // Cancel only app1
        guardInstance.cancel(processIdentifier: 4001)

        #expect(!guardInstance.isGuarding(processIdentifier: 4001))
        #expect(guardInstance.isGuarding(processIdentifier: 4002))
        #expect(guardInstance.isGuarding)

        // Notification for app1 should be ignored
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app1]
        )
        #expect(app1.hideCallCount == 0)

        // Notification for app2 should still suppress
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app2]
        )
        #expect(app2.hideCallCount == 1)
    }

    @Test("Independent timer expiration cleans up only the expired process")
    func independentTimerExpiration() async throws {
        let notificationCenter = NotificationCenter()
        let app1 = MockRunningApp(processIdentifier: 5001)
        let app2 = MockRunningApp(processIdentifier: 5002)

        var shouldSleepIndefinitely = false
        let guardInstance = FocusGuard(
            notificationCenter: notificationCenter,
            gracePeriod: .milliseconds(10),
            sleep: { _ in
                if shouldSleepIndefinitely {
                    try await Task.sleep(for: .seconds(100))
                }
            }
        )

        guardInstance.startGuarding(app: app1)
        try await Task.sleep(for: .milliseconds(50))

        #expect(!guardInstance.isGuarding(processIdentifier: 5001))

        // Now start app2 with long timer so it does not expire
        shouldSleepIndefinitely = true
        guardInstance.startGuarding(app: app2)
        #expect(guardInstance.isGuarding(processIdentifier: 5002))
        #expect(guardInstance.isGuarding)

        // app2 responds to notifications
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app2]
        )
        #expect(app2.hideCallCount == 1)

        // Clean up
        guardInstance.cancel()
        #expect(!guardInstance.isGuarding)
    }
}
