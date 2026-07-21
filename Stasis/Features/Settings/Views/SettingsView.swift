import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var chargingSettingsModel: ChargingSettingsModel

    private let capabilities: DeviceCapabilities
    private let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? ""
    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
        _chargingSettingsModel = State(initialValue: ChargingSettingsModel())
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                SettingsSidebarRow(tab: tab, isSelected: selectedTab == tab)
                    .tag(tab)
            }.safeAreaInset(
                edge: .bottom,
                content: {
                    VStack {
                        Text("Stasis")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Version: \(version)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                }
            )
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(210)
            .padding(.top, SettingsLayout.sidebarTopPadding)
            .tint(.gray)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .dashboard:
                    DashboardSettingsView()
                case .charging:
                    ChargingSettingsView(
                        capabilities: capabilities,
                        settingsModel: chargingSettingsModel
                    )
                case .advanced:
                    AdvancedSettingsView(
                        batteryPercentageState: chargingSettingsModel
                            .batteryPercentageState
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    SettingsView(
        capabilities: DeviceCapabilities(
            chargingControl: true,
            adapterControl: true,
            hasMagSafe: true,
            magsafeLEDControl: true
        )
    )
}
