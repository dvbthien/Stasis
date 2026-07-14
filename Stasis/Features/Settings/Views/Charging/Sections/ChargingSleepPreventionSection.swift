import SwiftUI

struct ChargingSleepPreventionSection: View {
  @Bindable var state: SleepPreventionSettingsState
  let isSupported: Bool

  private var isEnabled: Binding<Bool> {
    Binding(
      get: { isSupported && state.settings?.isEnabled == true },
      set: { state.setEnabled(isSupported ? $0 : false) }
    )
  }

  var body: some View {
    Section {
      if state.settings != nil {
        Toggle("Disable sleep until charge limit", isOn: isEnabled)
          .disabled(!isSupported)
      } else {
        ProgressView()
      }

      if !isSupported {
        SettingsInlineMessage(
          title: Text("Sleep prevention is unavailable in this charge-control mode."),
          message: Text("Firmware charge limits continue to work during sleep without a legacy sleep assertion.")
        )
      }

      if let errorMessage = state.errorMessage {
        SettingsInlineMessage(
          title: Text("Couldn’t save sleep prevention settings."),
          message: Text(errorMessage)
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
