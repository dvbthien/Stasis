import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var chargingSettingsModel: ChargingSettingsModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
            .padding(.top, SettingsLayout.sidebarTopPadding)
            .frame(minWidth: 190, minHeight: 560)
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
            .frame(minWidth: 570, minHeight: 560)
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
