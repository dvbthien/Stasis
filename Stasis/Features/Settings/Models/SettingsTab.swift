import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
  case general = "General"
  case dashboard = "Dashboard"
  case charging = "Charging"
  case advanced = "Advanced"

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .general: return "General"
    case .dashboard: return "Dashboard"
    case .charging: return "Charging"
    case .advanced: return "Advanced"
    }
  }

  var icon: String {
    switch self {
    case .general:
      return "gearshape"
    case .dashboard:
      return "chart.xyaxis.line"
    case .charging:
      return "battery.100.bolt"
    case .advanced:
      return "slider.horizontal.3"
    }
  }
}
