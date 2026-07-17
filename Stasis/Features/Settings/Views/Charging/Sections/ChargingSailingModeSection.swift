import SwiftUI

struct ChargingSailingModeSection: View {
  @Bindable var state: ThresholdSettingsState
  @State private var draftSailingDelta = 5
  @State private var isEditingSailingDelta = false

  let isSupported: Bool

  private var hasChargingControl: Bool {
    isSupported && (state.settings?.chargeLimit ?? 50) > 50
  }

  private var sailingMode: Binding<Bool> {
    Binding(
      get: { hasChargingControl && state.settings?.sailingModeEnabled == true },
      set: { state.setSailingEnabled(hasChargingControl ? $0 : false) }
    )
  }

  private var sailingResumePercentage: Int {
    (state.settings?.chargeLimit ?? 80) - draftSailingDelta
  }

  private var maximumSailingDelta: Int {
    max(1, min(20, (state.settings?.chargeLimit ?? 80) - 50))
  }

  var body: some View {
    Section {
      if state.settings != nil {
        Toggle("Enable sailing mode", isOn: sailingMode)
          .disabled(!hasChargingControl)
      } else {
        ProgressView()
      }

      if !hasChargingControl {
        SettingsInlineMessage(
          title: Text("Charging control is not supported on this device."),
          message: Text("Sailing mode requires charging control support from this Mac.")
        )
      }

      if hasChargingControl && state.settings?.sailingModeEnabled == true {
        SettingsValueSlider(
          "Threshold below limit",
          value: $draftSailingDelta,
          range: 1...maximumSailingDelta,
          valueLabel: { "\($0)%" },
          onEditingChanged: { isEditing in
            isEditingSailingDelta = isEditing
          }
        )

        LabeledContent("Charging resumes at") {
          Text("\(sailingResumePercentage)%")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }

      if let errorMessage = state.errorMessage,
         state.failedSettings?.chargeLimit == state.settings?.chargeLimit {
        SettingsRetryMessage(
          title: Text("Couldn’t save sailing mode settings."),
          message: Text(errorMessage),
          retry: state.retryLastSave
        )
      }
    } header: {
      SettingsSectionHeader(
        "Sailing Mode",
        message:
          "Automatically resume charging when the battery drops below the threshold relative to your charge limit."
      )
    }
    .onAppear(perform: synchronizeDraft)
    .onChange(of: draftSailingDelta) { _, sailingDelta in
      state.setSailingDelta(sailingDelta)
    }
    .onChange(of: state.settings?.sailingDelta) { _, _ in
      guard !isEditingSailingDelta else { return }
      synchronizeDraft()
    }
  }

  private func synchronizeDraft() {
    draftSailingDelta = min(state.settings?.sailingDelta ?? 5, maximumSailingDelta)
  }
}
