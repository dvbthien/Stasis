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
        newConnection.exportedInterface = NSXPCInterface(with: ChargingDaemonProtocol.self)
        newConnection.exportedObject = commandHandler
        newConnection.remoteObjectInterface = NSXPCInterface(
            with: ChargingDaemonClientProtocol.self
        )

        let clientID = UUID()
        let proxy = newConnection.remoteObjectProxyWithErrorHandler { [weak clients] _ in
            clients?.remove(id: clientID)
        }
        if let client = proxy as? ChargingDaemonClientProtocol {
            clients.add(client, id: clientID)
        }

        newConnection.invalidationHandler = { [weak clients] in
            clients?.remove(id: clientID)
        }
        newConnection.interruptionHandler = { [weak clients] in
            clients?.remove(id: clientID)
        }
        newConnection.resume()
        logger.info(
            "Accepted validated XPC client with pid \(newConnection.processIdentifier, privacy: .public)"
        )
        return true
    }
}
