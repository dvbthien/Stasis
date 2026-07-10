import SwiftUI

struct ChargingSailingModeSection: View {
  @Binding var sailingMode: Bool
  @Binding var sailingModeLimit: Int
  let sailingResumePercentage: Int
  let hasChargingControl: Bool

  var body: some View {
    Section {
      Toggle("Enable sailing mode", isOn: $sailingMode)
        .disabled(!hasChargingControl)

      if !hasChargingControl {
        SettingsInlineMessage(
          title: Text("Charging control is not supported on this device."),
          message: Text("Sailing mode requires charging control support from this Mac.")
        )
      }

      if hasChargingControl && sailingMode {
        SettingsValueSlider(
          "Threshold below limit",
          value: $sailingModeLimit,
          range: 1...20,
          valueLabel: { "\($0)%" }
        )

        LabeledContent("Charging resumes at") {
          Text("\(sailingResumePercentage)%")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
    } header: {
      SettingsSectionHeader(
        "Sailing Mode",
        message: "Automatically resume charging when the battery drops below the threshold relative to your charge limit."
      )
    }
  }
}
