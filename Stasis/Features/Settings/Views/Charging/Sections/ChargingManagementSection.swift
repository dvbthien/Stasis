import SwiftUI

struct ChargingManagementSection: View {
  @Binding var manageCharging: Bool
  @Binding var chargeLimit: Int
  let hasAnyControl: Bool
  let shouldShowChargingControls: Bool
  let isCheckingChargingDaemon: Bool
  let shouldShowApprovalPrompt: Bool
  let displayedStatusMessage: String?
  let shouldShowChargingControlError: Bool
  let helperStatus: ChargingHelperStatus
  let connectionStatus: ChargingDaemonConnectionStatus
  let openApprovalSettings: () -> Void
  let checkApprovalStatus: () -> Void
  let requestEnableChargingManagement: () -> Void
  let reconnectChargingDaemon: () -> Void

  var body: some View {
    Section {
      Toggle("Manage charging", isOn: $manageCharging)
        .disabled(!hasAnyControl || isCheckingChargingDaemon)

      if !hasAnyControl {
        SettingsInlineMessage(
          title: Text("Charge management is unavailable on this Mac."),
          message: Text(
            "Stasis can still monitor battery status, but this hardware does not expose charging or adapter controls."
          )
        )
      }

      if shouldShowApprovalPrompt {
        LabeledContent {
          HStack(spacing: SettingsLayout.controlSpacing) {
            Button("Open Login Items", systemImage: "gear") {
              openApprovalSettings()
            }

            Button("Check Again", systemImage: "arrow.clockwise") {
              checkApprovalStatus()
            }
          }
          .padding(.top, 4)
        } label: {
          Text("Approve Stasis in Login Items to enable charge management.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      if let displayedStatusMessage, shouldShowChargingControlError {
        ChargingDaemonStatusRow(
          message: displayedStatusMessage,
          isLoading: isCheckingChargingDaemon,
          helperStatus: helperStatus,
          connectionStatus: connectionStatus,
          install: requestEnableChargingManagement,
          openApprovalSettings: openApprovalSettings,
          retry: requestEnableChargingManagement,
          reconnect: reconnectChargingDaemon
        )
      }

      if shouldShowChargingControls {
        SettingsValueSlider(
          "Charge limit",
          value: $chargeLimit,
          range: 50...100,
          step: 5,
          valueLabel: { "\($0)%" }
        )
      }
    } header: {
      SettingsSectionHeader(
        "Charge Management",
        message: "Limit the maximum charge level to extend battery lifespan."
      )
    }
  }
}
