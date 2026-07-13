import SwiftUI

struct ChargingDischargeSection: View {
  @Binding var automaticDischarge: Bool
  let isSupported: Bool

  var body: some View {
    Section {
      Toggle("Automatic discharge", isOn: $automaticDischarge)
        .disabled(!isSupported)

      if !isSupported {
        SettingsInlineMessage(
          title: Text("Automatic discharge is unavailable in this charge-control mode."),
          message: Text("The daemon only enables this feature when direct charging and adapter control are both supported.")
        )
      }
    } header: {
      SettingsSectionHeader(
        "Discharge",
        message:
          "Discharge the battery to your charge limit when plugged in above the target level."
      )
    }
  }
}
