typealias ManagementSettingsState = ChargingSettingsGroupState<ChargingManagementSettings>

extension ChargingSettingsGroupState where Settings == ChargingManagementSettings {
  func setEnabled(_ enabled: Bool) {
    set(.init(isEnabled: enabled))
  }
}
