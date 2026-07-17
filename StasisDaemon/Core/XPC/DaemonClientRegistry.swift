import Foundation

final class DaemonClientRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [UUID: any ChargingDaemonClientProtocol] = [:]

    func add(_ client: any ChargingDaemonClientProtocol, id: UUID) {
        lock.withLock {
            clients[id] = client
        }
    }

    func remove(id: UUID) {
        lock.withLock {
            clients[id] = nil
        }
    }

    func publishSnapshot(_ payload: Data) {
        currentClients().forEach { $0.stateDidChange(payload) }
    }

    private func currentClients() -> [any ChargingDaemonClientProtocol] {
        lock.withLock { Array(clients.values) }
    }
}
