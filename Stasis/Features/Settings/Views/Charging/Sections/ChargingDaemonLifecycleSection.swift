import SwiftUI

struct ChargingDaemonLifecycleSection: View {
  let helperStatus: ChargingHelperStatus
  let isUninstalling: Bool
  let isBusy: Bool
  let errorMessage: String?
  let requestUninstall: () -> Void

  var body: some View {
    Section {
      HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.controlSpacing) {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionHeaderSpacing) {
          Text("Background Service")

          Text("Controls charging while Stasis isn't open.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isUninstalling {
          HStack(spacing: SettingsLayout.inlineMessageSpacing) {
            ProgressView()
              .controlSize(.small)

            Text("Removing…")
              .foregroundStyle(.secondary)
          }
        } else {
          Text(statusText)
            .foregroundStyle(.secondary)

          Button("Remove…", role: .destructive) {
            requestUninstall()
          }
          .disabled(isBusy)
        }
      }

      if let errorMessage {
        SettingsInlineMessage(
          title: Text("Couldn’t remove the background service."),
          message: Text(errorMessage)
        )
      }
    }
  }

  private var statusText: String {
    switch helperStatus {
    case .installed:
      "Active"
    case .requiresApproval:
      "Needs Approval"
    case .notInstalled:
      "Inactive"
    }
  }
}
