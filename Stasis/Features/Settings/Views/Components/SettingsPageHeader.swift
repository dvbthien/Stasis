import SwiftUI

struct SettingsPageHeader: View {
  let title: LocalizedStringKey
  let message: LocalizedStringKey

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.headerSpacing) {
      Text(title)
        .font(.title2)
        .bold()

      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, SettingsLayout.pageHeaderVerticalPadding)
  }
}
