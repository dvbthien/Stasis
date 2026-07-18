import SwiftUI

struct SettingsView: View {
  @State private var selectedTab: SettingsTab = .general
  @State private var chargingSettingsModel: ChargingSettingsModel

  private let capabilities: DeviceCapabilities
  private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  init(capabilities: DeviceCapabilities) {
    self.capabilities = capabilities
    _chargingSettingsModel = State(initialValue: ChargingSettingsModel())
  }

  var body: some View {
    NavigationSplitView() {
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
      .modifier(HideWindowTitle())
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
      .modifier(HideWindowTitle())
    }
    .modifier(HideWindowTitle())
    .frame(minWidth: 760, minHeight: 560)
  }
}

/// Keeps SwiftUI from re-asserting "Stasis Settings" into the window title on
/// tab switches or sidebar collapse — unlike the didUpdate observer in
/// SettingsSceneController, which only clears it a frame later and flickers.
/// On macOS 15+ the title toolbar item is removed outright; on macOS 14 an
/// empty title is set instead (`Text(verbatim:)` so no "" key leaks into the
/// localization catalog).
private struct HideWindowTitle: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content.toolbar(removing: .title)
    } else {
      content.navigationTitle(Text(verbatim: ""))
    }
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
