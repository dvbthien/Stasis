typealias HeatProtectionSettingsState = ChargingSettingsGroupState<HeatProtectionSettings>

extension ChargingSettingsGroupState where Settings == HeatProtectionSettings {
  func setEnabled(_ enabled: Bool) {
    guard var draft = settings else { return }
    draft.isEnabled = enabled
    set(draft)
  }

  func setTemperatureLimit(_ limit: Int) {
    guard var draft = settings else { return }
    draft.temperatureLimit = limit
    set(draft)
  }
}
