import SwiftUI

struct ChargingHeatProtectionSection: View {
  @Binding var enableHeatProtectionMode: Bool
  @Binding var heatProtectionLimit: Int
  let hasChargingControl: Bool

  var body: some View {
    Section {
      Toggle("Enable heat protection", isOn: $enableHeatProtectionMode)
        .disabled(!hasChargingControl)

      if !hasChargingControl {
        SettingsInlineMessage(
          title: Text("Charging control is not supported on this device."),
          message: Text("Heat protection requires charging control support from this Mac.")
        )
      }

      if hasChargingControl && enableHeatProtectionMode {
        SettingsValueSlider(
          "Temperature limit",
          value: $heatProtectionLimit,
          range: 30...50,
          valueLabel: { "\($0)°C" }
        )
      }
    } header: {
      SettingsSectionHeader(
        "Heat Protection",
        message: "Pause charging when the battery temperature exceeds the threshold."
      )
    }
  }
}
