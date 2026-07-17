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
      daemonStatus: .installed,
      connectionStatus: .connected,
      manageCharging: true,
      isVerifying: false,
      errorMessage: nil
    )
  )
}

#Preview("Manage Off Daemon Ready") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Manage Off Daemon Ready",
      daemonStatus: .installed,
      connectionStatus: .connected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil
    )
  )
}

#Preview("Removing Background Service") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Removing Background Service",
      daemonStatus: .installed,
      connectionStatus: .connected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil,
      isUninstalling: true
    )
  )
}

#Preview("Remove Background Service Failed") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Remove Background Service Failed",
      daemonStatus: .installed,
      connectionStatus: .connected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil,
      uninstallErrorMessage: "The background service could not be removed."
    )
  )
}

#Preview("Checking Daemon") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Checking Daemon",
      daemonStatus: .installed,
      connectionStatus: .connecting,
      manageCharging: false,
      isVerifying: true,
      errorMessage: "Checking Daemon"
    )
  )
}

#Preview("Connecting") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Connecting",
      daemonStatus: .installed,
      connectionStatus: .connecting,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil
    )
  )
}

#Preview("Disconnected") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Disconnected",
      daemonStatus: .installed,
      connectionStatus: .disconnected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: "Charging daemon is disconnected."
    )
  )
}

#Preview("Invalidated") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Invalidated",
      daemonStatus: .installed,
      connectionStatus: .invalidated,
      manageCharging: false,
      isVerifying: false,
      errorMessage: "Charging daemon connection was invalidated."
    )
  )
}

#Preview("Requires Approval") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Requires Approval",
      daemonStatus: .requiresApproval,
      connectionStatus: .disconnected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: "Approve Stasis in System Settings to enable charge management."
    )
  )
}

#Preview("Inactive Daemon") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Inactive Daemon",
      daemonStatus: .notInstalled,
      connectionStatus: .disconnected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil
    )
  )
}

#Preview("Setting Up Daemon") {
  ChargingSettingsPreviewContainer(
    state: ChargingSettingsPreviewState(
      title: "Setting Up Daemon",
      daemonStatus: .notInstalled,
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
      daemonStatus: .installed,
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
      daemonStatus: .installed,
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
      daemonStatus: .installed,
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
      daemonStatus: .installed,
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
      daemonStatus: .installed,
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
      daemonStatus: .installed,
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
      daemonStatus: .installed,
      connectionStatus: .connected,
      manageCharging: false,
      isVerifying: false,
      errorMessage: nil
    )
  )
  .frame(width: 520, height: 420)
}
