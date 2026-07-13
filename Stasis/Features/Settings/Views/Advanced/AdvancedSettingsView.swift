import Defaults
import SwiftUI

struct AdvancedSettingsView: View {
  @Default(.restartOnClose) private var restartOnClose
  @Bindable var chargingSettingsModel: ChargingSettingsModel

  private var useHardwarePercentage: Binding<Bool> {
    Binding(
      get: { chargingSettingsModel.settings.useHardwarePercentage },
      set: { chargingSettingsModel.set(\.useHardwarePercentage, to: $0) }
    )
  }

  var body: some View {
    Form {
      SettingsPageHeader(
        title: "Advanced",
        message: "Fine-tune battery readings and maintenance behavior."
      )

      Section {
        Toggle("Use hardware percentage", isOn: useHardwarePercentage)

        if chargingSettingsModel.settings.useHardwarePercentage {
          SettingsInlineMessage(
            title: Text(
              "Hardware percentage can differ from the calibrated value macOS shows in the battery menu."
            ),
            message: Text("Use this only if you prefer raw battery readings.")
          )
        }

        if let errorMessage = chargingSettingsModel.errorMessage {
          SettingsInlineMessage(
            title: Text("Couldn’t save battery reading settings."),
            message: Text(errorMessage)
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
    .disabled(chargingSettingsModel.isSaving)
  }
}

#Preview {
  AdvancedSettingsView(
    chargingSettingsModel: .preview(managementEnabled: true)
  )
}
