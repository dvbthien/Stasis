import SwiftUI

struct ChargingDischargeSection: View {
  @Binding var automaticDischarge: Bool
  let hasAdapterControl: Bool

  var body: some View {
    Section {
      Toggle("Automatic discharge", isOn: $automaticDischarge)
        .disabled(!hasAdapterControl)

      if !hasAdapterControl {
        SettingsInlineMessage(
          title: Text("Adapter control is not supported on this device."),
          message: Text("Automatic discharge requires adapter control support from this Mac.")
        )
      }
    } header: {
      SettingsSectionHeader(
        "Discharge",
        message: "Discharge the battery to your charge limit when plugged in above the target level."
      )
    }
  }
}
