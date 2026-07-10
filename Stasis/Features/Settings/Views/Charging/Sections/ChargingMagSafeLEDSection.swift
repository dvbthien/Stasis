import SwiftUI
import smc_power

struct ChargingMagSafeLEDSection: View {
  @Binding var manageMagSafeLED: Bool
  @Binding var heatProtectionMagSafeLEDState: MagSafeLEDState
  let hasChargingControl: Bool
  let hasMagSafeLEDControl: Bool
  let isHeatProtectionEnabled: Bool

  var body: some View {
    Section {
      Toggle("Manage MagSafe LED", isOn: $manageMagSafeLED)
        .disabled(!hasMagSafeLEDControl)

      if !hasMagSafeLEDControl {
        SettingsInlineMessage(
          title: Text("MagSafe LED control is not supported on this device."),
          message: Text(
            "Stasis can still manage charging, but this Mac does not expose MagSafe LED controls."
          )
        )
      }

      if hasMagSafeLEDControl,
        manageMagSafeLED,
        hasChargingControl,
        isHeatProtectionEnabled
      {
        Picker(
          "LED during heat protection",
          selection: $heatProtectionMagSafeLEDState
        ) {
          Text("Off").tag(MagSafeLEDState.off)
          Text("Green").tag(MagSafeLEDState.green)
          Text("Orange").tag(MagSafeLEDState.orange)
          Text("Blinking Orange Slow").tag(MagSafeLEDState.blinkOrangeSlow)
          Text("Blinking Orange Fast").tag(MagSafeLEDState.blinkOrangeFast)
        }
      }
    } header: {
      Text("MagSafe LED Control")
    }
  }
}
