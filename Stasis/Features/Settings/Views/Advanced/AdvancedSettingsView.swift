import Defaults
import SwiftUI

struct AdvancedSettingsView: View {
  @Default(.restartOnClose) private var restartOnClose
  @Bindable var batteryPercentageState: BatteryPercentageSettingsState

  private var useHardwarePercentage: Binding<Bool> {
    Binding(
      get: { batteryPercentageState.settings?.useHardwarePercentage ?? false },
      set: { batteryPercentageState.setUseHardwarePercentage($0) }
    )
  }

  var body: some View {
    Form {
      SettingsPageHeader(
        title: "Advanced",
        message: "Fine-tune battery readings and charging behavior."
      )

      Section {
        Toggle("Use hardware percentage", isOn: useHardwarePercentage)

        if batteryPercentageState.settings?.useHardwarePercentage == true {
          SettingsInlineMessage(
            title: Text(
              "Hardware percentage can differ from the calibrated value macOS shows in the battery menu."
            ),
            message: Text("Use this only if you prefer raw battery readings.")
          )
        }

        if let errorMessage = batteryPercentageState.errorMessage {
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
      .disabled(batteryPercentageState.settings == nil || batteryPercentageState.isSaving)

      Section {
        Toggle("Restart Stasis when Settings closes", isOn: $restartOnClose)
      } header: {
        SettingsSectionHeader(
          "Memory Management",
          message: "Restart Stasis after closing Settings to release memory used by the settings interface."
        )
      }
    }
    .settingsFormLayout()
  }
}

#Preview {
  AdvancedSettingsView(
    batteryPercentageState: ChargingSettingsModel.preview(managementEnabled: true).batteryPercentageState
  )
}
