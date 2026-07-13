import Foundation
import os.log

final class StasisDaemonXPCServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    static let machServiceName = "com.srimanachanta.stasis-daemon"

    private let listener: NSXPCListener
    private let commandHandler: ChargingDaemonCommandHandler
    private let clientValidator: any DaemonClientValidating
    private let clients: DaemonClientRegistry
    private let logger = Logger(
        subsystem: "com.srimanachanta.stasis-daemon",
        category: "XPCServer"
    )

    init(
        commandHandler: ChargingDaemonCommandHandler,
        clientValidator: any DaemonClientValidating,
        clients: DaemonClientRegistry,
        listener: NSXPCListener = NSXPCListener(
            machServiceName: "com.srimanachanta.stasis-daemon"
        )
    ) {
        self.commandHandler = commandHandler
        self.clientValidator = clientValidator
        self.clients = clients
        self.listener = listener
    }

    func start() {
        listener.delegate = self
        listener.resume()
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

        newConnection.invalidationHandler = { [weak clients, weak scopedHandler] in
            clients?.remove(id: clientID)
            scopedHandler?.connectionInvalidated()
        }
        newConnection.interruptionHandler = { [weak scopedHandler] in
            scopedHandler?.connectionInvalidated()
        }
        newConnection.resume()
        logger.info(
            "Accepted validated XPC client with pid \(newConnection.processIdentifier, privacy: .public)"
        )
        return true
    }
}
