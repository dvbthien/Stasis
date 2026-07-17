import SwiftUI
import Observation

// Shared between SwiftUI's NavigationSplitView and the AppKit toolbar button
// used to toggle it, since the sidebar collapse control lives in the
// AppKit-level NSToolbar rather than in SwiftUI's `.toolbar` modifier.
@Observable
final class SettingsSidebarState {
  var columnVisibility: NavigationSplitViewVisibility = .all

  func toggle() {
    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
  }
}
