import XCTest

@testable import Stasis

@MainActor
final class ChargingServiceStatusPresentationTests: XCTestCase {
    func testDeterminingStatusTakesPrecedence() {
        let presentation = makePresentation(
            daemonStatus: .notInstalled,
            connectionStatus: .disconnected,
            isDeterminingStatus: true,
            hasOperationError: true
        )

        XCTAssertEqual(presentation.status, .checking)
        XCTAssertNil(presentation.recoveryAction)
        XCTAssertFalse(presentation.canRemoveService)
    }

    func testDaemonAvailabilityTakesPrecedenceOverConnection() {
        let cases: [(
            ChargingDaemonStatus,
            ChargingServiceSemanticStatus
        )] = [
            (.notInstalled, .notInstalled),
            (.requiresApproval, .needsApproval),
        ]

        for (daemonStatus, expectedStatus) in cases {
            let presentation = makePresentation(
                daemonStatus: daemonStatus,
                connectionStatus: .connected
            )

            XCTAssertEqual(presentation.status, expectedStatus)
            XCTAssertNil(presentation.recoveryAction)
            XCTAssertFalse(presentation.canRemoveService)
        }
    }

    func testConnectingIsChecking() {
        let presentation = makePresentation(connectionStatus: .connecting)

        XCTAssertEqual(presentation.status, .checking)
        XCTAssertNil(presentation.recoveryAction)
        XCTAssertFalse(presentation.canRemoveService)
    }

    func testNotInstalledOperationErrorCanTryAgain() {
        let presentation = makePresentation(
            daemonStatus: .notInstalled,
            connectionStatus: .disconnected,
            hasOperationError: true
        )

        XCTAssertEqual(presentation.status, .notInstalled)
        XCTAssertEqual(presentation.recoveryAction, .tryAgain)
        XCTAssertFalse(presentation.canRemoveService)
    }

    func testConnectedIsReadyAndRemovable() {
        let presentation = makePresentation(connectionStatus: .connected)

        XCTAssertEqual(presentation.status, .ready)
        XCTAssertNil(presentation.recoveryAction)
        XCTAssertTrue(presentation.canRemoveService)
    }

    func testConnectedOperationErrorCanRetry() {
        let presentation = makePresentation(
            connectionStatus: .connected,
            hasOperationError: true
        )

        XCTAssertEqual(presentation.status, .ready)
        XCTAssertEqual(presentation.recoveryAction, .tryAgain)
        XCTAssertTrue(presentation.canRemoveService)
    }

    func testStartupFailureCanTryAgain() {
        let presentation = makePresentation(
            connectionStatus: .startupFailed("Unavailable")
        )

        XCTAssertEqual(presentation.status, .connectionIssue)
        XCTAssertEqual(presentation.recoveryAction, .tryAgain)
        XCTAssertFalse(presentation.canRemoveService)
    }

    func testConnectionFailuresCanReconnect() {
        let statuses: [ChargingDaemonConnectionStatus] = [
            .disconnected,
            .interrupted,
            .invalidated,
            .runtimeFailed("Unavailable"),
        ]

        for connectionStatus in statuses {
            let presentation = makePresentation(
                connectionStatus: connectionStatus
            )

            XCTAssertEqual(presentation.status, .connectionIssue)
            XCTAssertEqual(presentation.recoveryAction, .reconnect)
            XCTAssertFalse(presentation.canRemoveService)
        }
    }

    private func makePresentation(
        daemonStatus: ChargingDaemonStatus = .installed,
        connectionStatus: ChargingDaemonConnectionStatus,
        isDeterminingStatus: Bool = false,
        hasOperationError: Bool = false
    ) -> ChargingServiceStatusPresentation {
        ChargingServiceStatusPresentation(
            daemonStatus: daemonStatus,
            connectionStatus: connectionStatus,
            isDeterminingStatus: isDeterminingStatus,
            hasOperationError: hasOperationError
        )
    }
}
