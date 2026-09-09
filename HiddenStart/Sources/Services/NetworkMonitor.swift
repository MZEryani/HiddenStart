import Foundation
import Network
import Combine

@MainActor
public final class NetworkMonitor: ObservableObject, NetworkMonitoring {
    @Published public private(set) var isConnected: Bool = false

    public var isConnectedPublisher: AnyPublisher<Bool, Never> {
        $isConnected.eraseToAnyPublisher()
    }

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var isStarted = false

    public init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(label: "com.mzeryani.HiddenStart.NetworkMonitor")
    ) {
        self.monitor = monitor
        self.queue = queue
    }

    public func startMonitoring() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfies = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = satisfies
            }
        }
        monitor.start(queue: queue)
    }

    public func stopMonitoring() {
        guard isStarted else { return }
        isStarted = false
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
