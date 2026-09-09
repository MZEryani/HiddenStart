import AppKit
import Foundation

@MainActor
public final class FocusGuard: NSObject, FocusGuarding {
    private let notificationCenter: NotificationCenter
    private let gracePeriod: Duration
    private let sleep: @MainActor (Duration) async throws -> Void

    private var guardedApp: (any RunningAppRepresentable)?
    private var guardedProcessIdentifier: pid_t?
    private var timeoutTask: Task<Void, Never>?

    public private(set) var isGuarding: Bool = false

    public init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        gracePeriod: Duration = .seconds(10),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.notificationCenter = notificationCenter
        self.gracePeriod = gracePeriod
        self.sleep = sleep
        super.init()
    }

    deinit {
        timeoutTask?.cancel()
        notificationCenter.removeObserver(self)
    }

    public func startGuarding(app: any RunningAppRepresentable) {
        cancel()
        isGuarding = true
        self.guardedApp = app
        self.guardedProcessIdentifier = app.processIdentifier

        notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        timeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(self.gracePeriod)
                self.stopGuarding()
            } catch {
                // Task cancelled
            }
        }
    }

    public func cancel() {
        stopGuarding()
    }

    private func stopGuarding() {
        isGuarding = false
        notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        guardedApp = nil
        guardedProcessIdentifier = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard isGuarding, let guardedApp, let guardedProcessIdentifier else { return }
        if let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? any RunningAppRepresentable,
           activated.processIdentifier == guardedProcessIdentifier {
            guardedApp.hide()
        }
    }
}
