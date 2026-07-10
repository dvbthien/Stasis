import Defaults
import SwiftUI

struct DashboardSettingsView: View {
    @Default(.showPowerSource) private var showPowerSource
    @Default(.showTimeTillDischarge) private var showTimeTillDischarge
    @Default(.showUptime) private var showUptime
    @Default(.showBatteryMode) private var showBatteryMode
    @Default(.showBatteryTemperature) private var showBatteryTemperature
    @Default(.showBatteryCycleCount) private var showBatteryCycleCount
    @Default(.showBatteryHealth) private var showBatteryHealth
    @Default(.showInternalPower) private var showInternalPower
    @Default(.showExternalPower) private var showExternalPower
    @Default(.showPowerDistribution) private var showPowerDistribution

    var body: some View {
        Form {
            SettingsPageHeader(
                title: "Dashboard",
                message: "Choose which live battery and power metrics appear in the menu bar dropdown."
            )

            Section {
                Toggle("Power source", isOn: $showPowerSource)
                Toggle("Time until discharge", isOn: $showTimeTillDischarge)
                Toggle("Uptime", isOn: $showUptime)
                Toggle("Battery mode", isOn: $showBatteryMode)
            } header: {
                SettingsSectionHeader(
                    "Status",
                    message: "General system and battery status information shown in the menu dropdown."
                )
            }

            Section {
                Toggle("Cycle count", isOn: $showBatteryCycleCount)
                Toggle("Health", isOn: $showBatteryHealth)
                Toggle("Temperature", isOn: $showBatteryTemperature)
            } header: {
                SettingsSectionHeader(
                    "Battery Health",
                    message: "Battery condition details shown alongside current status."
                )
            }

            Section {
                Toggle("Battery Power Metrics", isOn: $showInternalPower)
                Toggle("Adapter Power Metrics", isOn: $showExternalPower)
                Toggle("Power distribution diagram", isOn: $showPowerDistribution)
            } header: {
                SettingsSectionHeader(
                    "Power",
                    message: "Power flow and adapter metrics shown in the menu dropdown."
                )
            }
        }
        .settingsFormLayout()
    }
}

#Preview {
    DashboardSettingsView()
}
