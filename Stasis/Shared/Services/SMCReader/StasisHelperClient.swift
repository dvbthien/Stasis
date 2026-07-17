import Foundation
import os.log

@MainActor
final class StasisHelperClient {
    static let shared = StasisHelperClient()

    private static let serviceName = Constants.Identity.smcReaderService

    private var connection: NSXPCConnection?
    private let logger = Logger.stasis("StasisHelperClient")

    func readAllMetrics() async throws -> SMCTelemetryMetrics {
        let payload = try await execute("Read SMC telemetry metrics") { helper, reply in
            helper.readAllMetrics(reply: reply)
        }
        return try DaemonPayloadCodec.decode(SMCTelemetryMetrics.self, from: payload)
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func helperProxy(
        errorHandler: @escaping @Sendable (Error) -> Void
    ) -> StasisHelperProtocol? {
        if connection == nil {
            logger.debug("Opening SMC reader helper connection")
            let newConnection = NSXPCConnection(serviceName: Self.serviceName)
            newConnection.remoteObjectInterface = NSXPCInterface(
                with: (any StasisHelperProtocol).self
            )
            newConnection.invalidationHandler = { [weak self] in
                Task { @MainActor in
                    self?.connection = nil
                }
            }
            newConnection.interruptionHandler = { [weak self] in
                Task { @MainActor in
                    self?.connection = nil
                }
            }
            newConnection.resume()
            connection = newConnection
        }

        return connection?.remoteObjectProxyWithErrorHandler(errorHandler)
            as? StasisHelperProtocol
    }

    private func execute(
        _ label: String,
        operation: @escaping (
            StasisHelperProtocol,
            @escaping @Sendable (Data?, String?) -> Void
        ) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let completion = SMCReaderCompletion(continuation: continuation)
            guard
                let helper = helperProxy(errorHandler: { error in
                    Task { @MainActor in
                        completion.resume(
                            throwing: XPCError.commandFailed(error.localizedDescription)
                        )
                    }
                })
            else {
                completion.resume(throwing: XPCError.serviceUnavailable)
                return
            }

            operation(helper) { payload, errorMessage in
                if let payload {
                    Task { @MainActor in
                        completion.resume(returning: payload)
                    }
                } else {
                    Task { @MainActor in
                        completion.resume(
                            throwing: XPCError.commandFailed(
                                errorMessage ?? "\(label) returned no data"
                            )
                        )
                    }
                }
            }
        }
    }
}

@MainActor
private final class SMCReaderCompletion: @unchecked Sendable {
    private var didResume = false
    private let continuation: CheckedContinuation<Data, Error>

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(returning payload: Data) {
        guard markResumed() else { return }
        continuation.resume(returning: payload)
    }

    func resume(throwing error: Error) {
        guard markResumed() else { return }
        continuation.resume(throwing: error)
    }

    private func markResumed() -> Bool {
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
