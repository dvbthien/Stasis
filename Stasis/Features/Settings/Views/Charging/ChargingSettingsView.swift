import Defaults
import SwiftUI
import smc_power

struct ChargingSettingsView: View {
  @Default(.manageCharging) private var manageCharging
  @Default(.chargeLimit) private var chargeLimit
  @Default(.sailingMode) private var sailingMode
  @Default(.sailingModeLimit) private var sailingModeLimit
  @Default(.automaticDischarge) private var automaticDischarge
  @Default(.disableSleepUntilChargeLimit) private var disableSleepUntilChargeLimit
  @Default(.enableHeatProtectionMode) private var enableHeatProtectionMode
  @Default(.heatProtectionLimit) private var heatProtectionLimit
  @Default(.manageMagSafeLED) private var manageMagSafeLED
  @Default(.heatProtectionMagSafeLEDState) private var heatProtectionMagSafeLEDState
  @State private var helperManager = ChargingDaemonManager.shared
  @State private var chargingController = ChargingManagementController()

  private let capabilities: DeviceCapabilities
  private let previewState: ChargingSettingsPreviewState?

  init(capabilities: DeviceCapabilities) {
    self.capabilities = capabilities
    self.previewState = nil
  }

  init(
    capabilities: DeviceCapabilities,
    previewState: ChargingSettingsPreviewState
  ) {
    self.capabilities = capabilities
    self.previewState = previewState
  }

  private var hasChargingControl: Bool {
    capabilities.chargingControl
  }

  private var hasAdapterControl: Bool {
    capabilities.adapterControl
  }

  private var hasMagSafe: Bool {
    capabilities.hasMagSafe
  }

  private var hasAnyControl: Bool {
    hasChargingControl || hasAdapterControl
  }

  private var sailingResumePercentage: Int {
    chargeLimit - sailingModeLimit
  }

  private var helperStatus: ChargingHelperStatus {
    previewState?.helperStatus ?? helperManager.helperStatus
  }

  private var connectionStatus: ChargingDaemonConnectionStatus {
    previewState?.connectionStatus ?? helperManager.connectionStatus
  }

  private var isManageChargingOn: Bool {
    guard hasAnyControl else { return false }
    return previewState?.manageCharging ?? manageCharging
  }

  private var automaticDischargeBinding: Binding<Bool> {
    Binding(
      get: { hasAdapterControl && automaticDischarge },
      set: { automaticDischarge = hasAdapterControl ? $0 : false }
    )
  }

  private var sailingModeBinding: Binding<Bool> {
    Binding(
      get: { hasChargingControl && sailingMode },
      set: { sailingMode = hasChargingControl ? $0 : false }
    )
  }

  private var heatProtectionModeBinding: Binding<Bool> {
    Binding(
      get: { hasChargingControl && enableHeatProtectionMode },
      set: { enableHeatProtectionMode = hasChargingControl ? $0 : false }
    )
  }

  private var magSafeLEDBinding: Binding<Bool> {
    Binding(
      get: { capabilities.magsafeLEDControl && manageMagSafeLED },
      set: { manageMagSafeLED = capabilities.magsafeLEDControl ? $0 : false }
    )
  }

  private var isCheckingChargingDaemon: Bool {
    previewState?.isVerifying ?? chargingController.flowState.isLoading
  }

  private var displayedChargingControlError: String? {
    previewState?.errorMessage ?? chargingController.flowState.message
  }

  private var setupStatusMessage: String? {
    isCheckingChargingDaemon ? displayedChargingControlError : nil
  }

  private var displayedStatusMessage: String? {
    setupStatusMessage ?? displayedChargingControlError
  }

  private var shouldShowChargingControlError: Bool {
    guard displayedStatusMessage != nil else { return false }
    if helperStatus == .requiresApproval { return false }
    return true
  }

  private var shouldShowApprovalPrompt: Bool {
    guard helperStatus == .requiresApproval else { return false }
    if previewState != nil { return true }
    return chargingController.flowState.showsApprovalPrompt
  }

  private var isChargingDaemonReady: Bool {
    helperStatus == .installed
      && connectionStatus == .connected
      && !isCheckingChargingDaemon
  }

  private var shouldShowChargingControls: Bool {
    isManageChargingOn && isChargingDaemonReady
  }

  private var manageChargingBinding: Binding<Bool> {
    Binding(
      get: { isManageChargingOn },
      set: { newValue in
        guard previewState == nil else { return }
        toggleManageCharging(newValue)
      }
    )
  }

  private var chargeLimitBinding: Binding<Int> {
    Binding(
      get: { chargeLimit },
      set: { chargeLimit = $0 }
    )
  }

  private var sailingModeLimitBinding: Binding<Int> {
    Binding(
      get: { sailingModeLimit },
      set: { sailingModeLimit = $0 }
    )
  }

  private var heatProtectionLimitBinding: Binding<Int> {
    Binding(
      get: { heatProtectionLimit },
      set: { heatProtectionLimit = $0 }
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
          hasAdapterControl: hasAdapterControl
        )

        ChargingSleepPreventionSection(
          disableSleepUntilChargeLimit: $disableSleepUntilChargeLimit
        )

        ChargingSailingModeSection(
          sailingMode: sailingModeBinding,
          sailingModeLimit: sailingModeLimitBinding,
          sailingResumePercentage: sailingResumePercentage,
          hasChargingControl: hasChargingControl
        )

        ChargingHeatProtectionSection(
          enableHeatProtectionMode: heatProtectionModeBinding,
          heatProtectionLimit: heatProtectionLimitBinding,
          hasChargingControl: hasChargingControl
        )

        if hasMagSafe {
          ChargingMagSafeLEDSection(
            manageMagSafeLED: magSafeLEDBinding,
            heatProtectionMagSafeLEDState: $heatProtectionMagSafeLEDState,
            hasChargingControl: hasChargingControl,
            hasMagSafeLEDControl: capabilities.magsafeLEDControl,
            isHeatProtectionEnabled: enableHeatProtectionMode
          )
        }
      }
    }
    .settingsFormLayout()
    .animation(.default, value: isManageChargingOn)
    .animation(.default, value: sailingMode)
    .animation(.default, value: enableHeatProtectionMode)
    .animation(.default, value: manageMagSafeLED)
    .animation(.default, value: helperStatus)
    .animation(.default, value: connectionStatus)
    .onAppear {
      guard previewState == nil else { return }
      resetUnsupportedSettings()
      chargingController.reconcileOnAppear(
        hasAnyControl: hasAnyControl,
        manageCharging: manageCharging,
        setManageCharging: { manageCharging = $0 }
      )
    }
    .onDisappear {
      guard previewState == nil else { return }
      chargingController.cancelPendingWork()
    }
    .onChange(of: helperManager.helperStatus) { _, newStatus in
      guard previewState == nil else { return }
      chargingController.handleHelperStatusChange(
        newStatus,
        setManageCharging: { manageCharging = $0 }
      )
    }
    .onChange(of: helperManager.connectionStatus) { _, newStatus in
      guard previewState == nil else { return }
      chargingController.handleConnectionStatusChange(
        newStatus,
        manageCharging: manageCharging,
        setManageCharging: { manageCharging = $0 }
      )
    }
  }

  private func runPreviewSafe(_ action: @escaping () -> Void) -> () -> Void {
    {
      guard previewState == nil else { return }
      action()
    }
  }

  private func toggleManageCharging(_ enabled: Bool) {
    if enabled {
      chargingController.requestEnable(
        hasAnyControl: hasAnyControl,
        setManageCharging: { manageCharging = $0 }
      )
    } else {
      chargingController.disable(setManageCharging: { manageCharging = $0 })
    }
  }

  private func checkApprovalStatus() {
    chargingController.checkApprovalStatus(
      setManageCharging: { manageCharging = $0 }
    )
  }

  private func openApprovalSettings() {
    chargingController.openApprovalSettings()
  }

  private func requestEnableChargingManagement() {
    chargingController.requestEnable(
      hasAnyControl: hasAnyControl,
      setManageCharging: { manageCharging = $0 }
    )
  }

  private func reconnectChargingDaemon() {
    helperManager.disconnect()
    requestEnableChargingManagement()
  }

  private func resetUnsupportedSettings() {
    if !hasAnyControl {
      manageCharging = false
    }
    if !hasAdapterControl {
      automaticDischarge = false
    }
    if !hasChargingControl {
      sailingMode = false
      enableHeatProtectionMode = false
    }
    if !capabilities.magsafeLEDControl {
      manageMagSafeLED = false
    }
  }
}
