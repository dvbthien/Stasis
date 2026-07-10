import SwiftUI

struct SettingsSectionHeader: View {
  let title: LocalizedStringKey
  let message: LocalizedStringKey?

  init(_ title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
    self.title = title
    self.message = message
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionHeaderSpacing) {
      Text(title)

      if let message {
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}
