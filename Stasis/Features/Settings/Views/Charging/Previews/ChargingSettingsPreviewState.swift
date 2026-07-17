struct ChargingSettingsPreviewState {
  let title: String
  let daemonStatus: ChargingDaemonStatus
  let connectionStatus: ChargingDaemonConnectionStatus
  let manageCharging: Bool
  let isVerifying: Bool
  let errorMessage: String?
  let isUninstalling: Bool
  let uninstallErrorMessage: String?

  init(
    title: String,
    daemonStatus: ChargingDaemonStatus,
    connectionStatus: ChargingDaemonConnectionStatus,
    manageCharging: Bool,
    isVerifying: Bool,
    errorMessage: String?,
    isUninstalling: Bool = false,
    uninstallErrorMessage: String? = nil
  ) {
    self.title = title
    self.daemonStatus = daemonStatus
    self.connectionStatus = connectionStatus
    self.manageCharging = manageCharging
    self.isVerifying = isVerifying
    self.errorMessage = errorMessage
    self.isUninstalling = isUninstalling
    self.uninstallErrorMessage = uninstallErrorMessage
  }
}
