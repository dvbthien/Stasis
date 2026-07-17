import SwiftUI

struct SettingsView: View {
  @State private var selectedTab: SettingsTab = .general
  @State private var chargingSettingsModel: ChargingSettingsModel
  private var sidebarState: SettingsSidebarState

  private let capabilities: DeviceCapabilities
  private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  init(capabilities: DeviceCapabilities, sidebarState: SettingsSidebarState) {
    self.capabilities = capabilities
    self.sidebarState = sidebarState
    _chargingSettingsModel = State(initialValue: ChargingSettingsModel())
  }

  var body: some View {
    NavigationSplitView(
      columnVisibility: Binding(
        get: { sidebarState.columnVisibility },
        set: { sidebarState.columnVisibility = $0 }
      )
    ) {
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
      .navigationSplitViewColumnWidth(190)
      .listStyle(.sidebar)
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
            batteryPercentageState: chargingSettingsModel.batteryPercentageState
          )
        }
      }
    }
    .frame(minWidth: 760, minHeight: 560)
  }
}

#Preview {
  SettingsView(
    capabilities: DeviceCapabilities(
      chargingControl: true,
      adapterControl: true,
      hasMagSafe: true,
      magsafeLEDControl: true
    ),
    sidebarState: SettingsSidebarState()
  )
}
