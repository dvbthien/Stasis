import SwiftUI

struct SettingsRetryMessage: View {
  let title: Text
  let message: Text
  let retry: () -> Void

  var body: some View {
    LabeledContent {
      Button("Try Again", systemImage: "arrow.clockwise", action: retry)
    } label: {
      SettingsInlineMessage(title: title, message: message)
    }
  }
}
