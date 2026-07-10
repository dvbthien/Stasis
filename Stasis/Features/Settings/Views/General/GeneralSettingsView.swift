import Defaults
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.batteryPercentageDisplayLocation) private var batteryPercentageDisplayLocation
    @Default(.showBatteryStateInStatusIcon) private var showBatteryStateInStatusIcon
    @Default(.disableNotifications) private var disableNotifications
    @Default(.showChargingStatusChangedNotification) private var showChargingStatusChangedNotification

    var body: some View {
        Form {
            SettingsPageHeader(
                title: "General",
                message: "Control how Stasis starts, appears in the menu bar, and sends notifications."
            )

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Section {
                Picker("Show percentage", selection: $batteryPercentageDisplayLocation) {
                    Text("Hidden").tag(PercentageDisplayLocation.hidden)
                    Text("Next to icon").tag(PercentageDisplayLocation.nextToIcon)
                    Text("Inside icon").tag(PercentageDisplayLocation.insideIcon)
                }
                Toggle("Show battery state", isOn: $showBatteryStateInStatusIcon)
            } header: {
                SettingsSectionHeader(
                    "Menu Bar Icon",
                    message: "Display battery percentage next to or inside the menu bar icon."
                )
            }

            Section {
                Toggle("Disable all notifications", isOn: $disableNotifications)
                Toggle("Charging status changed", isOn: $showChargingStatusChangedNotification)
                    .disabled(disableNotifications)
            } header: {
                SettingsSectionHeader(
                    "Notifications",
                    message: "Control when Stasis sends you notifications."
                )
            }
        }
        .settingsFormLayout()
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginService.shared.setLaunchAtLogin(newValue)
        }
    }
}

#Preview {
    GeneralSettingsView()
}
