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
