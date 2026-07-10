import SwiftUI

struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool

    var body: some View {
        Label {
            Text(tab.title)
                .font(.title3)
        } icon: {
            Image(systemName: tab.icon)
                .font(.body)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: SettingsLayout.sidebarIconWidth, alignment: .center)
        }
    }
}
