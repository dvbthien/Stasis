struct ChargingSettingsPreviewState {
  let title: String
  let helperStatus: ChargingHelperStatus
  let connectionStatus: ChargingDaemonConnectionStatus
  let manageCharging: Bool
  let isVerifying: Bool
  let errorMessage: String?
}
