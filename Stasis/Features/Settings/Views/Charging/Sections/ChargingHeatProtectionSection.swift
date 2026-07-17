import SwiftUI

struct ChargingHeatProtectionSection: View {
  @Bindable var state: HeatProtectionSettingsState
  @State private var draftTemperatureLimit = 40
  @State private var isEditingTemperatureLimit = false

  let hasChargingControl: Bool
  var isModeLimited = false

  private var isEnabled: Binding<Bool> {
    Binding(
      get: { hasChargingControl && state.settings?.isEnabled == true },
      set: { state.setEnabled(hasChargingControl ? $0 : false) }
    )
  }

  var body: some View {
    Section {
      if state.settings != nil {
        Toggle("Enable heat protection", isOn: isEnabled)
          .disabled(!hasChargingControl)
      } else {
        ProgressView()
      }

      if !hasChargingControl {
        if isModeLimited {
          SettingsInlineMessage(
            title: Text("Heat protection is unavailable in this charge-control mode."),
            message: Text(
              "This Mac's firmware enforces the charge limit itself, so Stasis cannot pause charging when the battery runs hot."
            )
          )
        } else {
          SettingsInlineMessage(
            title: Text("Charging control is not supported on this device."),
            message: Text("Heat protection requires charging control support from this Mac.")
          )
        }
      }

      if hasChargingControl && state.settings?.isEnabled == true {
        SettingsValueSlider(
          "Temperature limit",
          value: $draftTemperatureLimit,
          range: 30...50,
          valueLabel: { "\($0)°C" },
          onEditingChanged: { isEditing in
            isEditingTemperatureLimit = isEditing
          }
        )
      }

      if let errorMessage = state.errorMessage {
        SettingsInlineMessage(
          title: Text("Couldn’t save heat protection settings."),
          message: Text(errorMessage)
        )
      }
    } header: {
      SettingsSectionHeader(
        "Heat Protection",
        message: "Pause charging when the battery temperature exceeds the threshold."
      )
    }
    .onAppear(perform: synchronizeDraft)
    .onChange(of: draftTemperatureLimit) { _, temperatureLimit in
      state.setTemperatureLimit(temperatureLimit)
    }
    .onChange(of: state.settings?.temperatureLimit) { _, _ in
      guard !isEditingTemperatureLimit else { return }
      synchronizeDraft()
    }
  }

  private func synchronizeDraft() {
    draftTemperatureLimit = state.settings?.temperatureLimit ?? 40
  }
}
