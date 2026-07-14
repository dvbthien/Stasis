import SwiftUI

struct ChargingMagSafeLEDSection: View {
  @Bindable var state: MagSafeLEDSettingsState
  @Bindable var heatProtectionState: HeatProtectionSettingsState

  let hasChargingControl: Bool
  let hasMagSafeLEDControl: Bool

  private var isEnabled: Binding<Bool> {
    Binding(
      get: { hasMagSafeLEDControl && state.settings?.isEnabled == true },
      set: { state.setEnabled(hasMagSafeLEDControl ? $0 : false) }
    )
  }

  private var selectedHeatProtectionState: Binding<MagSafeLEDState> {
    Binding(
      get: { state.settings?.heatProtectionState ?? .blinkOrangeSlow },
      set: { state.setHeatProtectionState($0) }
    )
  }

  var body: some View {
    Section {
      if state.settings != nil {
        Toggle("Manage MagSafe LED", isOn: isEnabled)
          .disabled(!hasMagSafeLEDControl)
      } else {
        ProgressView()
      }

      if !hasMagSafeLEDControl {
        SettingsInlineMessage(
          title: Text("MagSafe LED control is not supported on this device."),
          message: Text(
            "Stasis can still manage charging, but this Mac does not expose MagSafe LED controls."
          )
        )
      }

      if hasMagSafeLEDControl,
        state.settings?.isEnabled == true,
        hasChargingControl,
        heatProtectionState.settings?.isEnabled == true
      {
        Picker(
          "LED during heat protection",
          selection: selectedHeatProtectionState
        ) {
          Text("Off").tag(MagSafeLEDState.off)
          Text("Green").tag(MagSafeLEDState.green)
          Text("Orange").tag(MagSafeLEDState.orange)
          Text("Blinking Orange Slow").tag(MagSafeLEDState.blinkOrangeSlow)
          Text("Blinking Orange Fast").tag(MagSafeLEDState.blinkOrangeFast)
        }
      }

      if let errorMessage = state.errorMessage {
        SettingsInlineMessage(
          title: Text("Couldn’t save MagSafe LED settings."),
          message: Text(errorMessage)
        )
      }
    } header: {
      Text("MagSafe LED Control")
    }
  }
}
