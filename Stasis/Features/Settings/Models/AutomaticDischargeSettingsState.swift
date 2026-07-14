typealias AutomaticDischargeSettingsState = ChargingSettingsGroupState<AutomaticDischargeSettings>

extension ChargingSettingsGroupState where Settings == AutomaticDischargeSettings {
  func setEnabled(_ enabled: Bool) {
    set(.init(isEnabled: enabled))
  }
}
