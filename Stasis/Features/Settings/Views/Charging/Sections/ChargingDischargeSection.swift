import SwiftUI

struct ChargingDischargeSection: View {
  @Bindable var state: AutomaticDischargeSettingsState
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
        Toggle("Automatic discharge", isOn: isEnabled)
          .disabled(!isSupported)
      } else {
        ProgressView()
      }

      if !isSupported {
        SettingsInlineMessage(
          title: Text("Automatic discharge is unavailable in this charge-control mode."),
          message: Text("The daemon only enables this feature when direct charging and adapter control are both supported.")
        )
      }

      if let errorMessage = state.errorMessage {
        SettingsInlineMessage(
          title: Text("Couldn’t save automatic discharge settings."),
          message: Text(errorMessage)
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
