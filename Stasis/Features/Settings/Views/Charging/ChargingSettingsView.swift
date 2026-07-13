import SwiftUI
import smc_power

struct ChargingSettingsView: View {
  @State private var helperManager = ChargingDaemonManager.shared
  @State private var chargingController = ChargingManagementController()
  @Bindable var settingsModel: ChargingSettingsModel

  private let fallbackCapabilities: DeviceCapabilities
  private let previewState: ChargingSettingsPreviewState?

  init(
    capabilities: DeviceCapabilities,
    settingsModel: ChargingSettingsModel
  ) {
    fallbackCapabilities = capabilities
    previewState = nil
    self.settingsModel = settingsModel
  }

  init(
    capabilities: DeviceCapabilities,
    previewState: ChargingSettingsPreviewState
  ) {
    fallbackCapabilities = capabilities
    self.previewState = previewState
    settingsModel = ChargingSettingsModel.preview(
      managementEnabled: previewState.manageCharging
    )
  }

  private var hasChargingControl: Bool {
    settingsModel.capabilities?.chargingControl ?? fallbackCapabilities.chargingControl
  }

  private var hasAdapterControl: Bool {
    settingsModel.capabilities?.adapterControl ?? fallbackCapabilities.adapterControl
  }

  private var hasMagSafe: Bool {
    settingsModel.capabilities?.magSafeLEDKeyAvailable ?? fallbackCapabilities.hasMagSafe
  }

  private var hasAnyControl: Bool {
    if settingsModel.capabilities != nil {
      return settingsModel.availability.management
    }
    return hasChargingControl || hasAdapterControl
  }

  private var automaticDischargeSupported: Bool {
    settingsModel.capabilities?.automaticDischargeControl
      ?? (hasChargingControl && hasAdapterControl)
  }

  private var sailingModeSupported: Bool {
    settingsModel.capabilities?.sailingModeControl ?? hasChargingControl
  }

  private var sleepPreventionSupported: Bool {
    settingsModel.capabilities?.sleepHooks ?? hasChargingControl
  }

  private var heatProtectionSupported: Bool {
    settingsModel.capabilities?.heatProtectionControl ?? hasChargingControl
  }

  private var magSafeLEDSupported: Bool {
    settingsModel.capabilities?.magSafeLEDControl ?? fallbackCapabilities.magsafeLEDControl
  }

  private var sailingResumePercentage: Int {
    settingsModel.settings.chargeLimit - settingsModel.settings.sailingDelta
  }

  private var helperStatus: ChargingHelperStatus {
    previewState?.helperStatus ?? helperManager.helperStatus
  }

  private var connectionStatus: ChargingDaemonConnectionStatus {
    previewState?.connectionStatus ?? helperManager.connectionStatus
  }

  private var isManageChargingOn: Bool {
    guard hasAnyControl else { return false }
    return previewState?.manageCharging ?? settingsModel.settings.managementEnabled
  }

  private var isCheckingChargingDaemon: Bool {
    previewState?.isVerifying
      ?? (chargingController.flowState.isLoading || settingsModel.isSaving)
  }

  private var displayedChargingControlError: String? {
    previewState?.errorMessage
      ?? settingsModel.errorMessage
      ?? chargingController.flowState.message
  }

  private var displayedStatusMessage: String? {
    displayedChargingControlError
  }

  private var shouldShowChargingControlError: Bool {
    guard displayedStatusMessage != nil else { return false }
    return helperStatus != .requiresApproval
  }

  private var shouldShowApprovalPrompt: Bool {
    guard helperStatus == .requiresApproval else { return false }
    return previewState != nil || chargingController.flowState.showsApprovalPrompt
  }

  private var isChargingDaemonReady: Bool {
    helperStatus == .installed
      && connectionStatus == .connected
      && settingsModel.isLoaded
      && !chargingController.flowState.isLoading
  }

  private var shouldShowChargingControls: Bool {
    isManageChargingOn && isChargingDaemonReady
  }

  private var manageChargingBinding: Binding<Bool> {
    Binding(
      get: { isManageChargingOn },
      set: { enabled in
        guard previewState == nil else { return }
        toggleManageCharging(enabled)
      }
    )
  }

  private var chargeLimitBinding: Binding<Int> {
    Binding(
      get: { settingsModel.settings.chargeLimit },
      set: { settingsModel.set(\.chargeLimit, to: $0, debounced: true) }
    )
  }

  private var automaticDischargeBinding: Binding<Bool> {
    Binding(
      get: {
        automaticDischargeSupported && settingsModel.settings.automaticDischarge
      },
      set: {
        settingsModel.set(
          \.automaticDischarge,
          to: automaticDischargeSupported ? $0 : false
        )
      }
    )
  }

  private var sailingModeBinding: Binding<Bool> {
    Binding(
      get: { sailingModeSupported && settingsModel.settings.sailingModeEnabled },
      set: {
        settingsModel.set(
          \.sailingModeEnabled,
          to: sailingModeSupported ? $0 : false
        )
      }
    )
  }

  private var sailingModeLimitBinding: Binding<Int> {
    Binding(
      get: { settingsModel.settings.sailingDelta },
      set: { settingsModel.set(\.sailingDelta, to: $0, debounced: true) }
    )
  }

  private var sleepPreventionBinding: Binding<Bool> {
    Binding(
      get: {
        sleepPreventionSupported && settingsModel.settings.preventSleepUntilLimit
      },
      set: {
        settingsModel.set(
          \.preventSleepUntilLimit,
          to: sleepPreventionSupported ? $0 : false
        )
      }
    )
  }

  private var heatProtectionModeBinding: Binding<Bool> {
    Binding(
      get: {
        heatProtectionSupported && settingsModel.settings.heatProtectionEnabled
      },
      set: {
        settingsModel.set(
          \.heatProtectionEnabled,
          to: heatProtectionSupported ? $0 : false
        )
      }
    )
  }

  private var heatProtectionLimitBinding: Binding<Int> {
    Binding(
      get: { settingsModel.settings.heatProtectionLimit },
      set: { settingsModel.set(\.heatProtectionLimit, to: $0, debounced: true) }
    )
  }

  private var magSafeLEDBinding: Binding<Bool> {
    Binding(
      get: { magSafeLEDSupported && settingsModel.settings.manageMagSafeLED },
      set: {
        settingsModel.set(
          \.manageMagSafeLED,
          to: magSafeLEDSupported ? $0 : false
        )
      }
    )
  }

  private var heatProtectionLEDStateBinding: Binding<MagSafeLEDState> {
    Binding(
      get: {
        MagSafeLEDState(
          rawValue: settingsModel.settings.heatProtectionLEDStateRawValue
        ) ?? .blinkOrangeSlow
      },
      set: {
        settingsModel.set(\.heatProtectionLEDStateRawValue, to: $0.rawValue)
      }
    )
  }

  var body: some View {
    Form {
      SettingsPageHeader(
        title: "Charging",
        message: "Manage charging, battery protection, and MagSafe LED behavior."
      )

      ChargingManagementSection(
        manageCharging: manageChargingBinding,
        chargeLimit: chargeLimitBinding,
        hasAnyControl: hasAnyControl,
        shouldShowChargingControls: shouldShowChargingControls,
        isCheckingChargingDaemon: isCheckingChargingDaemon,
        shouldShowApprovalPrompt: shouldShowApprovalPrompt,
        displayedStatusMessage: displayedStatusMessage,
        shouldShowChargingControlError: shouldShowChargingControlError,
        helperStatus: helperStatus,
        connectionStatus: connectionStatus,
        openApprovalSettings: runPreviewSafe(openApprovalSettings),
        checkApprovalStatus: runPreviewSafe(checkApprovalStatus),
        requestEnableChargingManagement: runPreviewSafe(requestEnableChargingManagement),
        reconnectChargingDaemon: runPreviewSafe(reconnectChargingDaemon)
      )

      if shouldShowChargingControls {
        ChargingDischargeSection(
          automaticDischarge: automaticDischargeBinding,
          isSupported: automaticDischargeSupported
        )

        ChargingSleepPreventionSection(
          disableSleepUntilChargeLimit: sleepPreventionBinding,
          isSupported: sleepPreventionSupported
        )

        ChargingSailingModeSection(
          sailingMode: sailingModeBinding,
          sailingModeLimit: sailingModeLimitBinding,
          sailingResumePercentage: sailingResumePercentage,
          hasChargingControl: sailingModeSupported
        )

        ChargingHeatProtectionSection(
          enableHeatProtectionMode: heatProtectionModeBinding,
          heatProtectionLimit: heatProtectionLimitBinding,
          hasChargingControl: heatProtectionSupported
        )

        if hasMagSafe {
          ChargingMagSafeLEDSection(
            manageMagSafeLED: magSafeLEDBinding,
            heatProtectionMagSafeLEDState: heatProtectionLEDStateBinding,
            hasChargingControl: heatProtectionSupported,
            hasMagSafeLEDControl: magSafeLEDSupported,
            isHeatProtectionEnabled: settingsModel.settings.heatProtectionEnabled
          )
        }
      }
    }
    .settingsFormLayout()
    .disabled(previewState == nil && settingsModel.isSaving)
    .animation(.default, value: isManageChargingOn)
    .animation(.default, value: settingsModel.settings.sailingModeEnabled)
    .animation(.default, value: settingsModel.settings.heatProtectionEnabled)
    .animation(.default, value: settingsModel.settings.manageMagSafeLED)
    .animation(.default, value: helperStatus)
    .animation(.default, value: connectionStatus)
    .onAppear {
      guard previewState == nil else { return }
      chargingController.reconcileOnAppear(
        hasAnyControl: hasAnyControl,
        manageCharging: settingsModel.settings.managementEnabled
      )
    }
    .onDisappear {
      guard previewState == nil else { return }
      chargingController.cancelPendingWork()
    }
    .onChange(of: helperManager.helperStatus) { _, newStatus in
      guard previewState == nil else { return }
      chargingController.handleHelperStatusChange(
        newStatus
      )
    }
    .onChange(of: helperManager.connectionStatus) { _, newStatus in
      guard previewState == nil else { return }
      chargingController.handleConnectionStatusChange(
        newStatus,
        manageCharging: settingsModel.settings.managementEnabled
      )
    }
  }

  private func runPreviewSafe(_ action: @escaping () -> Void) -> () -> Void {
    { if previewState == nil { action() } }
  }

  private func toggleManageCharging(_ enabled: Bool) {
    if enabled {
      chargingController.requestEnable(
        hasAnyControl: hasAnyControl,
        setManageCharging: { settingsModel.setManagementEnabled($0) }
      )
    } else {
      chargingController.disable(
        setManageCharging: { settingsModel.setManagementEnabled($0) }
      )
    }
  }

  private func checkApprovalStatus() {
    chargingController.checkApprovalStatus(
      setManageCharging: { settingsModel.setManagementEnabled($0) }
    )
  }

  private func openApprovalSettings() {
    chargingController.openApprovalSettings()
  }

  private func requestEnableChargingManagement() {
    chargingController.requestEnable(
      hasAnyControl: hasAnyControl,
      setManageCharging: { settingsModel.setManagementEnabled($0) }
    )
  }

  private func reconnectChargingDaemon() {
    helperManager.disconnect()
    requestEnableChargingManagement()
  }
}
