import Defaults
import SwiftUI

struct AdvancedSettingsView: View {
    @Default(.useHardwarePercentage) var useHardwarePercentage
    @Default(.restartOnClose) var restartOnClose
    
    var body: some View {
        Form {
            Section {
                Toggle("Use hardware percentage", isOn: $useHardwarePercentage)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery Reading")
                    Text(
                        "Use the raw battery percentage instead of the macOS calibrated value."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Toggle("Restart on Close", isOn: $restartOnClose)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory Management")
                    Text(
                        "Control how Stasis manages memory."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
    }
}

#Preview {
    AdvancedSettingsView()
}
