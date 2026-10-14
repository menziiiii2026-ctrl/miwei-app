import Foundation
import Network

@MainActor
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.dinefolio.sync-network")
    private let becameAvailable: @MainActor () -> Void
    private var started = false

    init(becameAvailable: @escaping @MainActor () -> Void) {
        self.becameAvailable = becameAvailable
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.becameAvailable() }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
