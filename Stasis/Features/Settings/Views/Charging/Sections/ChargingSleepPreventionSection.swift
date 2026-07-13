import SwiftUI

struct ChargingSleepPreventionSection: View {
  @Binding var disableSleepUntilChargeLimit: Bool
  let isSupported: Bool

  var body: some View {
    Section {
      Toggle("Disable sleep until charge limit", isOn: $disableSleepUntilChargeLimit)
        .disabled(!isSupported)

      if !isSupported {
        SettingsInlineMessage(
          title: Text("Sleep prevention is unavailable in this charge-control mode."),
          message: Text("Firmware charge limits continue to work during sleep without a legacy sleep assertion.")
        )
      }
    } header: {
      SettingsSectionHeader(
        "Sleep Prevention",
        message:
          "Prevent your Mac from sleeping while charging towards the charge limit. Sleep is re-enabled once the limit is reached or the adapter is disconnected."
      )
    }
  }
}
