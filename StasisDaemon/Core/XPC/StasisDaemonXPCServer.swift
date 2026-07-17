import Foundation
import os.log

final class StasisDaemonXPCServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    static let machServiceName = Constants.Identity.daemon

    private let listener: NSXPCListener
    private let commandHandler: ChargingDaemonCommandHandler
    private let clientValidator: any DaemonClientValidating
    private let clients: DaemonClientRegistry
    private var isRunning = false
    // NSXPCListenerDelegate does not retain accepted connections for you —
    // the delegate is responsible for keeping a strong reference to each one
    // for as long as it should stay alive. We key by clientID so teardown is
    // a simple dictionary removal. Guarded by a lock because delegate
    // callbacks are not guaranteed to run on the main thread.
    private let activeConnectionsLock = NSLock()
    private var activeConnections: [UUID: NSXPCConnection] = [:]
    private let logger = Logger(
        subsystem: Constants.Identity.daemon,
        category: "XPCServer"
    )

    init(
        commandHandler: ChargingDaemonCommandHandler,
        clientValidator: any DaemonClientValidating,
        clients: DaemonClientRegistry,
        listener: NSXPCListener = NSXPCListener(
            machServiceName: Constants.Identity.daemon
        )
    ) {
        self.commandHandler = commandHandler
        self.clientValidator = clientValidator
        self.clients = clients
        self.listener = listener
    }

    func start() {
        guard !isRunning else { return }
        listener.delegate = self
        listener.resume()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        listener.suspend()
        isRunning = false
        let connections = activeConnectionsLock.withLock {
            defer { activeConnections.removeAll() }
            return Array(activeConnections.values)
        }
        connections.forEach { $0.invalidate() }
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard clientValidator.isValid(processIdentifier: newConnection.processIdentifier) else {
            logger.error(
                "Rejected XPC client with pid \(newConnection.processIdentifier, privacy: .public)"
            )
            return false
        }

        newConnection.setCodeSigningRequirement(clientValidator.codeSigningRequirement)
        let clientID = UUID()
        let scopedHandler = commandHandler.scoped(to: clientID)
        newConnection.exportedInterface = NSXPCInterface(with: ChargingDaemonProtocol.self)
        newConnection.exportedObject = scopedHandler
        newConnection.remoteObjectInterface = NSXPCInterface(
            with: ChargingDaemonClientProtocol.self
        )

        let proxy = newConnection.remoteObjectProxyWithErrorHandler {
            [weak clients, weak scopedHandler] _ in
            clients?.remove(id: clientID)
            scopedHandler?.connectionInvalidated()
        }
        if let client = proxy as? ChargingDaemonClientProtocol {
            clients.add(client, id: clientID)
        }

        newConnection.invalidationHandler = { [weak self, weak clients, weak scopedHandler] in
            clients?.remove(id: clientID)
            scopedHandler?.connectionInvalidated()
            if let self {
                self.activeConnectionsLock.withLock {
                    _ = self.activeConnections.removeValue(forKey: clientID)
                }
            }
        }
        newConnection.interruptionHandler = { [weak scopedHandler] in
            scopedHandler?.connectionInvalidated()
        }
        activeConnectionsLock.withLock {
            activeConnections[clientID] = newConnection
        }
        newConnection.resume()
        logger.info(
            "Accepted validated XPC client with pid \(newConnection.processIdentifier, privacy: .public)"
        )
        return true
    }
}
