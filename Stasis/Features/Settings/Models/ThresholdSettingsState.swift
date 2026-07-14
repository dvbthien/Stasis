typealias ThresholdSettingsState = ChargingSettingsGroupState<ChargingThresholdSettings>

extension ChargingSettingsGroupState where Settings == ChargingThresholdSettings {
  func setChargeLimit(_ limit: Int) {
    guard var draft = settings else { return }
    draft.chargeLimit = limit
    if limit - draft.sailingDelta < 50 {
      draft.sailingDelta = max(0, limit - 50)
    }
    if draft.sailingDelta == 0 {
      draft.sailingModeEnabled = false
    }
    set(draft)
  }

  func setSailingEnabled(_ enabled: Bool) {
    guard var draft = settings else { return }

    if enabled, draft.sailingDelta == 0 {
      let maximumDelta = min(20, max(0, draft.chargeLimit - 50))
      guard maximumDelta > 0 else { return }
      draft.sailingDelta = min(ChargingThresholdSettings().sailingDelta, maximumDelta)
    }

    draft.sailingModeEnabled = enabled
    set(draft)
  }

  func setSailingDelta(_ delta: Int) {
    guard var draft = settings else { return }
    draft.sailingDelta = min(delta, max(0, draft.chargeLimit - 50))
    set(draft)
  }
}
