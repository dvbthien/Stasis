import SwiftUI

struct ChargingDaemonStatusRow: View {
  let message: String
  let presentation: ChargingServiceStatusPresentation
  let retry: () -> Void
  let reconnect: () -> Void

  var body: some View {
    LabeledContent {
      recoveryAction
    } label: {
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var recoveryAction: some View {
    switch presentation.recoveryAction {
    case .tryAgain:
      Button("Try Again", systemImage: "arrow.clockwise") {
        retry()
      }
    case .reconnect:
      Button("Reconnect", systemImage: "arrow.clockwise") {
        reconnect()
      }
    case nil:
      EmptyView()
    }
  }
}
