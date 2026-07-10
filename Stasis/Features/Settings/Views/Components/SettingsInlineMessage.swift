import SwiftUI

struct SettingsInlineMessage: View {
  let title: Text
  let message: Text

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.inlineMessageSpacing) {
      title
        .font(.subheadline)

      message
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
