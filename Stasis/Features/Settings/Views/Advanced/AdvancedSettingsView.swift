import Defaults
import SwiftUI

struct AdvancedSettingsView: View {
  @Default(.useHardwarePercentage) private var useHardwarePercentage
  @Default(.restartOnClose) private var restartOnClose

  var body: some View {
    Form {
      SettingsPageHeader(
        title: "Advanced",
        message: "Fine-tune battery readings and maintenance behavior."
      )

      Section {
        Toggle("Use hardware percentage", isOn: $useHardwarePercentage)

        if useHardwarePercentage {
          SettingsInlineMessage(
            title: Text(
              "Hardware percentage can differ from the calibrated value macOS shows in the battery menu."
            ),
            message: Text("Use this only if you prefer raw battery readings.")
          )
        }
      } header: {
        SettingsSectionHeader(
          "Battery Reading",
          message: "Use the raw battery percentage instead of the macOS calibrated value."
        )
      }

      Section {
        Toggle("Restart the app when Settings closes", isOn: $restartOnClose)
      } header: {
        SettingsSectionHeader(
          "Memory Management",
          message: "Control how Stasis manages memory."
        )
      }
    }
    .settingsFormLayout()
  }
}

#Preview {
  AdvancedSettingsView()
}
