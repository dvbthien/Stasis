import SwiftUI

struct ChargingSettingsView: View {
  @State private var helperManager = ChargingDaemonManager.shared
  @State private var chargingController = ChargingManagementController()
  @State private var showsUninstallConfirmation = false
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
    if previewState == nil {
      return settingsModel.availability.canAttemptManagement
    }
    return fallbackCapabilities.chargingControl || fallbackCapabilities.adapterControl
  }

  private var capabilitiesResolved: Bool {
    previewState != nil || settingsModel.availability.isResolved
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
    (settingsModel.threshold?.chargeLimit ?? 80) - (settingsModel.threshold?.sailingDelta ?? 5)
  }

  private var helperStatus: ChargingHelperStatus {
    previewState?.helperStatus ?? helperManager.helperStatus
  }

  private var connectionStatus: ChargingDaemonConnectionStatus {
    previewState?.connectionStatus ?? helperManager.connectionStatus
  }

  private var isManageChargingOn: Bool {
    guard hasAnyControl else { return false }
    return previewState?.manageCharging ?? settingsModel.management?.isEnabled ?? false
  }

  private var isCheckingChargingDaemon: Bool {
    previewState.map { $0.isVerifying || $0.isUninstalling }
      ?? (chargingController.flowState.isLoading || settingsModel.isSaving)
  }

  private var isUninstalling: Bool {
    previewState?.isUninstalling ?? (chargingController.flowState == .uninstalling)
  }

  private var uninstallErrorMessage: String? {
    previewState?.uninstallErrorMessage
      ?? chargingController.flowState.uninstallErrorMessage
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
      && settingsModel.management != nil
      && capabilitiesResolved
      && !chargingController.flowState.isLoading
  }

  private var shouldShowChargingControls: Bool {
    isManageChargingOn && isChargingDaemonReady && settingsModel.threshold != nil
  }

  private var shouldShowLoadedChargingGroups: Bool {
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
      get: { settingsModel.threshold?.chargeLimit ?? 80 },
      set: { value in
        settingsModel.updateChargingThreshold(debounced: true) {
          $0.chargeLimit = value
          if value - $0.sailingDelta < 50 {
            $0.sailingDelta = max(0, value - 50)
          }
          if $0.sailingDelta == 0 {
            $0.sailingModeEnabled = false
          }
        }
      }
    )
  }

  private var automaticDischargeBinding: Binding<Bool> {
    Binding(
      get: {
        automaticDischargeSupported && settingsModel.automaticDischarge?.isEnabled == true
      },
      set: {
        settingsModel.setAutomaticDischargeEnabled(automaticDischargeSupported ? $0 : false)
      }
    )
  }

  private var sailingModeBinding: Binding<Bool> {
    Binding(
      get: { sailingModeSupported && settingsModel.threshold?.sailingModeEnabled == true },
      set: {
        let value = sailingModeSupported ? $0 : false
        settingsModel.updateChargingThreshold { $0.sailingModeEnabled = value }
      }
    )
  }

  private var sailingModeLimitBinding: Binding<Int> {
    Binding(
      get: { settingsModel.threshold?.sailingDelta ?? 5 },
      set: { value in
        settingsModel.updateChargingThreshold(debounced: true) {
          $0.sailingDelta = min(value, max(0, $0.chargeLimit - 50))
        }
      }
    )
  }

  private var sleepPreventionBinding: Binding<Bool> {
    Binding(
      get: {
        sleepPreventionSupported && settingsModel.sleepPrevention?.isEnabled == true
      },
      set: {
        settingsModel.setSleepPreventionEnabled(sleepPreventionSupported ? $0 : false)
      }
    )
  }

  private var heatProtectionModeBinding: Binding<Bool> {
    Binding(
      get: {
        heatProtectionSupported && settingsModel.heatProtection?.isEnabled == true
      },
      set: {
        let value = heatProtectionSupported ? $0 : false
        settingsModel.updateHeatProtection { $0.isEnabled = value }
      }
    )
  }

  private var heatProtectionLimitBinding: Binding<Int> {
    Binding(
      get: { settingsModel.heatProtection?.temperatureLimit ?? 40 },
      set: { value in settingsModel.updateHeatProtection(debounced: true) { $0.temperatureLimit = value } }
    )
  }

  private var magSafeLEDBinding: Binding<Bool> {
    Binding(
      get: { magSafeLEDSupported && settingsModel.magSafeLED?.isEnabled == true },
      set: {
        let value = magSafeLEDSupported ? $0 : false
        settingsModel.updateMagSafeLED { $0.isEnabled = value }
      }
    )
  }

  private var heatProtectionLEDStateBinding: Binding<MagSafeLEDState> {
    Binding(
      get: {
        settingsModel.magSafeLED?.heatProtectionState ?? .blinkOrangeSlow
      },
      set: {
        let value = $0
        settingsModel.updateMagSafeLED { $0.heatProtectionState = value }
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

      if shouldShowLoadedChargingGroups {
        if settingsModel.automaticDischarge != nil {
        ChargingDischargeSection(
          automaticDischarge: automaticDischargeBinding,
          isSupported: automaticDischargeSupported
        )
        }

        if settingsModel.sleepPrevention != nil {
        ChargingSleepPreventionSection(
          disableSleepUntilChargeLimit: sleepPreventionBinding,
          isSupported: sleepPreventionSupported
        )
        }

        if settingsModel.threshold != nil {
        ChargingSailingModeSection(
          sailingMode: sailingModeBinding,
          sailingModeLimit: sailingModeLimitBinding,
          sailingResumePercentage: sailingResumePercentage,
          hasChargingControl: sailingModeSupported && (settingsModel.threshold?.chargeLimit ?? 50) > 50
        )
        }

        if settingsModel.heatProtection != nil {
        ChargingHeatProtectionSection(
          enableHeatProtectionMode: heatProtectionModeBinding,
          heatProtectionLimit: heatProtectionLimitBinding,
          hasChargingControl: heatProtectionSupported
        )
        }

        if hasMagSafe && settingsModel.magSafeLED != nil {
          ChargingMagSafeLEDSection(
            manageMagSafeLED: magSafeLEDBinding,
            heatProtectionMagSafeLEDState: heatProtectionLEDStateBinding,
            hasChargingControl: heatProtectionSupported,
            hasMagSafeLEDControl: magSafeLEDSupported,
            isHeatProtectionEnabled: settingsModel.heatProtection?.isEnabled == true
          )
        }
      }

      if helperStatus != .notInstalled || uninstallErrorMessage != nil {
        ChargingDaemonLifecycleSection(
          helperStatus: helperStatus,
          isUninstalling: isUninstalling,
          isBusy: isCheckingChargingDaemon,
          errorMessage: uninstallErrorMessage,
          requestUninstall: runPreviewSafe(showUninstallConfirmation)
        )
      }
    }
    .settingsFormLayout()
    .disabled(previewState == nil && (settingsModel.isSaving || isUninstalling))
    .animation(.default, value: isManageChargingOn)
    .animation(.default, value: settingsModel.threshold?.sailingModeEnabled)
    .animation(.default, value: settingsModel.heatProtection?.isEnabled)
    .animation(.default, value: settingsModel.magSafeLED?.isEnabled)
    .animation(.default, value: helperStatus)
    .animation(.default, value: connectionStatus)
    .alert("Remove Background Service?", isPresented: $showsUninstallConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) {
        requestUninstall()
      }
    } message: {
      Text(
        "Charging management will stop, and your Mac’s charging controls will return to their default state. You can enable it again at any time."
      )
    }
    .onAppear {
      guard previewState == nil else { return }
      chargingController.reconcileOnAppear(
        hasAnyControl: hasAnyControl,
        manageCharging: settingsModel.management?.isEnabled == true
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
        manageCharging: settingsModel.management?.isEnabled == true
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

  private func showUninstallConfirmation() {
    showsUninstallConfirmation = true
  }

  private func requestUninstall() {
    chargingController.requestUninstall(settingsModel: settingsModel)
  }
}
