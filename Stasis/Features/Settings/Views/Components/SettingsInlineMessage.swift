import SwiftUI

struct SettingsInlineMessage: View {
  private let title: Text?
  private let message: Text
  private let messageColor: Color

  init(title: Text, message: Text, messageColor: Color = .secondary) {
    self.title = title
    self.message = message
    self.messageColor = messageColor
  }

  init(message: Text, messageColor: Color = .secondary) {
    title = nil
    self.message = message
    self.messageColor = messageColor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.inlineMessageSpacing) {
      if let title {
        title
          .font(.subheadline)
      }

      message
        .font(.caption)
        .foregroundStyle(messageColor)
    }
  }
}
