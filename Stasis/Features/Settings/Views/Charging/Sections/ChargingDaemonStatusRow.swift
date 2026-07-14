import SwiftUI

struct ChargingDaemonStatusRow: View {
  let message: String
  let isLoading: Bool
  let helperStatus: ChargingHelperStatus
  let connectionStatus: ChargingDaemonConnectionStatus
  let install: () -> Void
  let openApprovalSettings: () -> Void
  let retry: () -> Void
  let reconnect: () -> Void

  var body: some View {
    LabeledContent {
      if isLoading {
        ProgressView()
          .controlSize(.small)
      } else {
        recoveryAction
      }
    } label: {
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var recoveryAction: some View {
    switch helperStatus {
    case .notInstalled:
      Button("Install Helper", systemImage: "wrench.and.screwdriver") {
        install()
      }
    case .requiresApproval:
      Button("Open Login Items", systemImage: "gear") {
        openApprovalSettings()
      }
    case .installed:
      switch connectionStatus {
      case .startupFailed:
        Button("Try Again", systemImage: "arrow.clockwise") {
          retry()
        }
      case .runtimeFailed, .interrupted, .invalidated, .disconnected:
        Button("Reconnect", systemImage: "arrow.clockwise") {
          reconnect()
        }
      case .connecting:
        EmptyView()
      case .connected:
        Button("Retry", systemImage: "arrow.clockwise") {
          retry()
        }
      }
    }
  }
}
