typealias MagSafeLEDSettingsState = ChargingSettingsGroupState<MagSafeLEDSettings>

extension ChargingSettingsGroupState where Settings == MagSafeLEDSettings {
  func setEnabled(_ enabled: Bool) {
    guard var draft = settings else { return }
    draft.isEnabled = enabled
    set(draft)
  }

  func setHeatProtectionState(_ state: MagSafeLEDState) {
    guard var draft = settings else { return }
    draft.heatProtectionState = state
    set(draft)
  }
}
