import AppKit
import Foundation

@MainActor
public final class FocusGuard: NSObject, FocusGuarding {
    private static let maxSuppressionStrikes = 2

    private struct GuardEntry {
        let app: any RunningAppRepresentable
        var strikeCount: Int = 0
        var timeoutTask: Task<Void, Never>?
    }

    private let notificationCenter: NotificationCenter
    private let gracePeriod: Duration
    private let sleep: @MainActor (Duration) async throws -> Void

    private var registry: [pid_t: GuardEntry] = [:]
    private var isObserving: Bool = false

    public var isGuarding: Bool {
        !registry.isEmpty
    }

    public init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        gracePeriod: Duration = .seconds(20),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.notificationCenter = notificationCenter
        self.gracePeriod = gracePeriod
        self.sleep = sleep
        super.init()
    }

    deinit {
        for entry in registry.values {
            entry.timeoutTask?.cancel()
        }
        notificationCenter.removeObserver(self)
    }

    public func isGuarding(processIdentifier: pid_t) -> Bool {
        registry[processIdentifier] != nil
    }

    public func startGuarding(app: any RunningAppRepresentable) {
        let pid = app.processIdentifier
        registry[pid]?.timeoutTask?.cancel()

        addObserversIfNeeded()

        let timeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(self.gracePeriod)
                self.stopGuarding(processIdentifier: pid)
            } catch {
                // Task cancelled
            }
        }

        registry[pid] = GuardEntry(
            app: app,
            strikeCount: 0,
            timeoutTask: timeoutTask
        )
    }

    public func cancel(processIdentifier: pid_t) {
        stopGuarding(processIdentifier: processIdentifier)
    }

    public func cancel() {
        for entry in registry.values {
            entry.timeoutTask?.cancel()
        }
        registry.removeAll()
        removeObserversIfEmpty()
    }

    private func stopGuarding(processIdentifier: pid_t) {
        if let entry = registry.removeValue(forKey: processIdentifier) {
            entry.timeoutTask?.cancel()
        }
        removeObserversIfEmpty()
    }

    private func addObserversIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationEvent(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationEvent(_:)),
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil
        )
    }

    private func removeObserversIfEmpty() {
        guard registry.isEmpty, isObserving else { return }
        isObserving = false
        notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        notificationCenter.removeObserver(self, name: NSWorkspace.didUnhideApplicationNotification, object: nil)
    }

    @objc private func handleApplicationEvent(_ notification: Notification) {
        guard let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? any RunningAppRepresentable else {
            return
        }
        let pid = activated.processIdentifier
        guard var entry = registry[pid] else { return }

        entry.app.hide()
        entry.strikeCount += 1

        if entry.strikeCount >= Self.maxSuppressionStrikes {
            stopGuarding(processIdentifier: pid)
        } else {
            registry[pid] = entry
        }
    }
}
