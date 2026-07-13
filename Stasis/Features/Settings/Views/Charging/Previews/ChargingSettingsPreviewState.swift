struct ChargingSettingsPreviewState {
  let title: String
  let helperStatus: ChargingHelperStatus
  let connectionStatus: ChargingDaemonConnectionStatus
  let manageCharging: Bool
  let isVerifying: Bool
  let errorMessage: String?
  let isUninstalling: Bool
  let uninstallErrorMessage: String?

  init(
    title: String,
    helperStatus: ChargingHelperStatus,
    connectionStatus: ChargingDaemonConnectionStatus,
    manageCharging: Bool,
    isVerifying: Bool,
    errorMessage: String?,
    isUninstalling: Bool = false,
    uninstallErrorMessage: String? = nil
  ) {
    self.title = title
    self.helperStatus = helperStatus
    self.connectionStatus = connectionStatus
    self.manageCharging = manageCharging
    self.isVerifying = isVerifying
    self.errorMessage = errorMessage
    self.isUninstalling = isUninstalling
    self.uninstallErrorMessage = uninstallErrorMessage
  }
}
