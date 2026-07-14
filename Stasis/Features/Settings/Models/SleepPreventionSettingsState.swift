typealias SleepPreventionSettingsState = ChargingSettingsGroupState<SleepPreventionSettings>

extension ChargingSettingsGroupState where Settings == SleepPreventionSettings {
  func setEnabled(_ enabled: Bool) {
    set(.init(isEnabled: enabled))
  }
}
