import SwiftUI

private struct SettingsFormLayout: ViewModifier {
  func body(content: Content) -> some View {
    content
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .contentMargins(.top, 0)
  }
}

extension View {
  func settingsFormLayout() -> some View {
    modifier(SettingsFormLayout())
  }
}
