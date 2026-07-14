typealias BatteryPercentageSettingsState = ChargingSettingsGroupState<BatteryPercentageSettings>

extension ChargingSettingsGroupState where Settings == BatteryPercentageSettings {
  func setUseHardwarePercentage(_ enabled: Bool) {
    set(.init(useHardwarePercentage: enabled))
  }
}
