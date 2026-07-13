import SwiftUI

extension DeviceCapabilities {
  fileprivate static let chargingSettingsPreview = DeviceCapabilities(
    chargingControl: true,
    adapterControl: true,
    hasMagSafe: true,
    magsafeLEDControl: true
  )

  fileprivate static let chargingSettingsAdapterUnsupportedPreview = DeviceCapabilities(
    chargingControl: true,
    adapterControl: false,
    hasMagSafe: true,
    magsafeLEDControl: true
  )

  fileprivate static let chargingSettingsChargingUnsupportedPreview = DeviceCapabilities(
    chargingControl: false,
    adapterControl: true,
    hasMagSafe: true,
    magsafeLEDControl: true
  )

  fileprivate static let chargingSettingsMagSafeLEDUnsupportedPreview = DeviceCapabilities(
    chargingControl: true,
    adapterControl: true,
    hasMagSafe: true,
    magsafeLEDControl: false
  )
}

private struct ChargingSettingsPreviewContainer: View {
  let state: ChargingSettingsPreviewState
  var capabilities: DeviceCapabilities = .chargingSettingsPreview

  var body: some View {
    ChargingSettingsView(
      capabilities: capabilities,
      previewState: state
    )
    .frame(width: 520, height: 680)
  }
}

#Preview("Ready") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Ready",
      helperStatus: .installed,
      connectionStatus: .connected,
      manageCharging: true,
      isVerifying: false,
      errorMessage: nil
    )
  )
}

#Preview("Manage Off Helper Ready") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Manage Off Helper Ready",
      helperStatus: .installed,
      connectionStatus: .connected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil
    )
  )
}

#Preview("Checking Helper") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Checking Helper",
      helperStatus: .installed,
      connectionStatus: .connecting,
      manageCharging: false,
      isVerifying: true,
      errorMessage: "Checking Helper"
    )
  )
}

#Preview("Requires Approval") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Requires Approval",
      helperStatus: .requiresApproval,
      connectionStatus: .disconnected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: "Approve Stasis in System Settings to enable charge management."
    )
  )
}

#Preview("Setting Up Helper") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Setting Up Helper",
      helperStatus: .notInstalled,
      connectionStatus: .disconnected,
      manageCharging: false,
      isVerifying: true,
      errorMessage: nil
    )
  )
}

#Preview("Startup Failed") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Startup Failed",
      helperStatus: .installed,
      connectionStatus: .startupFailed(
        "Charging daemon did not respond while verify charging daemon."),
      manageCharging: false,
      isVerifying: false,
      errorMessage: "Charging daemon did not respond while verify charging daemon."
    )
  )
}

#Preview("Runtime Interrupted") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Runtime Interrupted",
      helperStatus: .installed,
      connectionStatus: .interrupted,
      manageCharging: false,
      isVerifying: false,
      errorMessage: "Charging daemon connection was interrupted."
    )
  )
}

#Preview("Runtime Failed") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Runtime Failed",
      helperStatus: .installed,
      connectionStatus: .runtimeFailed(
        "Charging daemon did not respond while manage battery charging."),
      manageCharging: false,
      isVerifying: false,
      errorMessage: "Charging daemon did not respond while manage battery charging."
    )
  )
}

#Preview("Adapter Unsupported") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Adapter Unsupported",
      helperStatus: .installed,
      connectionStatus: .connected,
      manageCharging: true,
      isVerifying: false,
      errorMessage: nil
    ),
    capabilities: .chargingSettingsAdapterUnsupportedPreview
  )
}

#Preview("Charging Unsupported") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Charging Unsupported",
      helperStatus: .installed,
      connectionStatus: .connected,
      manageCharging: true,
      isVerifying: false,
      errorMessage: nil
    ),
    capabilities: .chargingSettingsChargingUnsupportedPreview
  )
}

#Preview("MagSafe LED Unsupported") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "MagSafe LED Unsupported",
      helperStatus: .installed,
      connectionStatus: .connected,
      manageCharging: true,
      isVerifying: false,
      errorMessage: nil
    ),
    capabilities: .chargingSettingsMagSafeLEDUnsupportedPreview
  )
}

#Preview("Unsupported") {
  ChargingSettingsView(
    capabilities: DeviceCapabilities(
      chargingControl: false,
      adapterControl: false,
      hasMagSafe: false,
      magsafeLEDControl: false
    ),
    previewState: ChargingSettingsPreviewState(
      title: "Unsupported",
      helperStatus: .installed,
      connectionStatus: .connected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil
    )
  )
  .frame(width: 520, height: 420)
}
