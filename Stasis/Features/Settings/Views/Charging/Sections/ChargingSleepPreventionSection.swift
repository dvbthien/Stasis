import SwiftUI

struct ChargingSleepPreventionSection: View {
  @Binding var disableSleepUntilChargeLimit: Bool

  var body: some View {
    Section {
      Toggle("Disable sleep until charge limit", isOn: $disableSleepUntilChargeLimit)
    } header: {
      SettingsSectionHeader(
        "Sleep Prevention",
        message: "Prevent your Mac from sleeping while charging towards the charge limit. Sleep is re-enabled once the limit is reached or the adapter is disconnected."
      )
    }
  }
}
