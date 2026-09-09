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
}
