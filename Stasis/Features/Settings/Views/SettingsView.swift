import SwiftUI
import smc_power

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let capabilities: DeviceCapabilities
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                SettingsSidebarRow(tab: tab, isSelected: selectedTab == tab)
                .tag(tab)
            }.safeAreaInset(edge: .bottom, content: {
                VStack {
                    Text("Stasis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Version: \(version)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom , 8)
                }
            })
            .navigationSplitViewColumnWidth(190)
            .listStyle(.automatic)
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
                    ChargingSettingsView(capabilities: capabilities)
                case .advanced:
                    AdvancedSettingsView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .imageScale(.large)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }


    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
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
