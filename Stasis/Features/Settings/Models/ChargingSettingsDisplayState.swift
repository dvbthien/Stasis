/// Resolved view state for the Charging settings screen, unifying the live
/// daemon-backed path and the design-time preview path so the view and its
/// sections only ever read one shape instead of coalescing `previewState?.X`
/// against a live value at every call site.
struct ChargingSettingsDisplayState: Equatable {
  let daemonStatus: ChargingDaemonStatus
  let connectionStatus: ChargingDaemonConnectionStatus
  let isManageChargingOn: Bool
  let isCheckingChargingDaemon: Bool
  let isDeterminingDaemonStatus: Bool
  let isUninstalling: Bool
  let uninstallErrorMessage: String?
  let displayedStatusMessage: String?

  /// Derived from the daemon status alone so the prompt appears even when
  /// approval is revoked outside the enable flow (e.g. after reinstalling
  /// the app with a changed daemon).
  var shouldShowApprovalPrompt: Bool {
    daemonStatus == .requiresApproval && !isUninstalling
  }

  init(
    daemonManager: ChargingDaemonManager,
    chargingController: ChargingManagementController,
    settingsModel: ChargingSettingsModel,
    hasAnyControl: Bool
  ) {
    daemonStatus = daemonManager.daemonStatus
    connectionStatus = daemonManager.connectionStatus
    isManageChargingOn = hasAnyControl
      && (settingsModel.managementState.settings?.isEnabled ?? false)
    isCheckingChargingDaemon = chargingController.isLoading
      || settingsModel.managementState.isSaving
    isDeterminingDaemonStatus = chargingController.isDeterminingDaemonStatus
    isUninstalling = chargingController.flowState == .uninstalling
    uninstallErrorMessage = chargingController.flowState.uninstallErrorMessage
    displayedStatusMessage = chargingController.flowState.message
  }

  init(previewState: ChargingSettingsPreviewState, hasAnyControl: Bool) {
    daemonStatus = previewState.daemonStatus
    connectionStatus = previewState.connectionStatus
    isManageChargingOn = hasAnyControl && previewState.manageCharging
    isCheckingChargingDaemon = previewState.isVerifying
      || previewState.isUninstalling
    isDeterminingDaemonStatus = previewState.isVerifying
    isUninstalling = previewState.isUninstalling
    uninstallErrorMessage = previewState.uninstallErrorMessage
    displayedStatusMessage = previewState.errorMessage
  }
}

/// User-triggered actions for the Charging settings screen. Preview mode
/// substitutes `.disabled` so the view body doesn't need to guard each
/// closure individually.
struct ChargingSettingsActions {
  let setManageCharging: (Bool) -> Void
  let openApprovalSettings: () -> Void
  let checkApprovalStatus: () -> Void
  let requestEnableChargingManagement: () -> Void
  let reconnectChargingDaemon: () -> Void
  let requestUninstall: () -> Void

  static let disabled = ChargingSettingsActions(
    setManageCharging: { _ in },
    openApprovalSettings: {},
    checkApprovalStatus: {},
    requestEnableChargingManagement: {},
    reconnectChargingDaemon: {},
    requestUninstall: {}
  )
}
