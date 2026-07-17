import SwiftUI

struct ChargingManagementSection: View {
  @Bindable var managementState: ManagementSettingsState
  @Bindable var thresholdState: ThresholdSettingsState
  @State private var draftChargeLimit = 80
  @State private var isEditingChargeLimit = false

  let previewManageCharging: Bool?
  let hasAnyControl: Bool
  let shouldShowChargingControls: Bool
  let isCheckingChargingDaemon: Bool
  let isDeterminingDaemonStatus: Bool
  let isUninstalling: Bool
  let shouldShowApprovalPrompt: Bool
  let displayedStatusMessage: String?
  let uninstallErrorMessage: String?
  let helperStatus: ChargingHelperStatus
  let connectionStatus: ChargingDaemonConnectionStatus
  let setManageCharging: (Bool) -> Void
  let openApprovalSettings: () -> Void
  let checkApprovalStatus: () -> Void
  let requestEnableChargingManagement: () -> Void
  let reconnectChargingDaemon: () -> Void
  let requestUninstall: () -> Void

  private var manageCharging: Binding<Bool> {
    Binding(
      get: {
        guard hasAnyControl else { return false }
        return previewManageCharging ?? managementState.settings?.isEnabled ?? false
      },
      set: { enabled in
        setManageCharging(enabled)
      }
    )
  }

  private var didChargeLimitSaveFail: Bool {
    guard let failedSettings = thresholdState.failedSettings else {
      return false
    }
    return failedSettings.chargeLimit != thresholdState.settings?.chargeLimit
  }

  private var serviceStatusPresentation: ChargingServiceStatusPresentation {
    ChargingServiceStatusPresentation(
      helperStatus: helperStatus,
      connectionStatus: connectionStatus,
      isDeterminingStatus: isDeterminingDaemonStatus,
      hasOperationError: displayedStatusMessage != nil
        && !isCheckingChargingDaemon
    )
  }

  var body: some View {
    Section {
      ChargingDaemonLifecycleSection(
        presentation: serviceStatusPresentation,
        isUninstalling: isUninstalling,
        isBusy: isCheckingChargingDaemon,
        errorMessage: uninstallErrorMessage,
        requestUninstall: requestUninstall
      )

      Toggle("Manage charging", isOn: manageCharging)
        .disabled(
          !hasAnyControl
            || isCheckingChargingDaemon
            || managementState.isSaving
        )

      if let errorMessage = managementState.errorMessage {
        SettingsRetryMessage(
          title: Text("Couldn’t save charge management settings."),
          message: Text(errorMessage),
          retry: managementState.retryLastSave
        )
      }

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

      if let displayedStatusMessage,
         serviceStatusPresentation.recoveryAction != nil {
        ChargingDaemonStatusRow(
          message: displayedStatusMessage,
          presentation: serviceStatusPresentation,
          retry: requestEnableChargingManagement,
          reconnect: reconnectChargingDaemon
        )
      }

      if shouldShowChargingControls {
        if thresholdState.settings != nil {
          SettingsValueSlider(
            "Charge limit",
            value: $draftChargeLimit,
            range: 50...100,
            step: 5,
            valueLabel: { "\($0)%" },
            onEditingChanged: { isEditing in
              isEditingChargeLimit = isEditing
            }
          )
        } else {
          ProgressView()
        }
      }

      if let errorMessage = thresholdState.errorMessage,
         didChargeLimitSaveFail {
        SettingsRetryMessage(
          title: Text("Couldn’t save charge limit."),
          message: Text(errorMessage),
          retry: thresholdState.retryLastSave
        )
      }
    } header: {
      SettingsSectionHeader(
        "Charge Management",
        message: "Limit the maximum charge level to extend battery lifespan."
      )
    }
    .onAppear(perform: synchronizeDraft)
    .onChange(of: draftChargeLimit) { _, chargeLimit in
      thresholdState.setChargeLimit(chargeLimit)
    }
    .onChange(of: thresholdState.settings?.chargeLimit) { _, _ in
      guard !isEditingChargeLimit else { return }
      synchronizeDraft()
    }
  }

  private func synchronizeDraft() {
    draftChargeLimit = thresholdState.settings?.chargeLimit ?? 80
  }
}
