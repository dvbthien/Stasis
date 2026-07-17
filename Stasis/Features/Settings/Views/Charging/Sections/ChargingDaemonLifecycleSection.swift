import SwiftUI

struct ChargingDaemonLifecycleSection: View {
    let presentation: ChargingServiceStatusPresentation
    let isUninstalling: Bool
    let isBusy: Bool
    let errorMessage: String?
    let requestUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: SettingsLayout.controlSpacing) {
                Text("Charging service")

                Text(
                    "Provides charging status in the background and applies policies when Manage charging is enabled."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: SettingsLayout.controlSpacing) {
                    (Text("Status") + Text(verbatim: ":"))
                        .font(.subheadline)

                    statusBadge
                }

                if let errorMessage {
                    SettingsInlineMessage(
                        message: Text(errorMessage),
                        messageColor: Color(
                            hue: 0.085, saturation: 0.75, brightness: 0.95
                        )
                    )
                }
            }

            Spacer(minLength: SettingsLayout.controlSpacing)

            if isUninstalling {
                HStack(spacing: SettingsLayout.inlineMessageSpacing) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Removing…")
                        .foregroundStyle(.secondary)
                }
            } else if presentation.canRemoveService {
                Button("Remove", role: .destructive) {
                    requestUninstall()
                }
                .font(.subheadline)
                .controlSize(.regular)
                .fixedSize()
                .disabled(isBusy)
                .help("Remove the charging service from this Mac.")
            }
        }
    }

    private var statusBadge: some View {
        let appearance = statusAppearance

        return HStack(spacing: SettingsLayout.inlineMessageSpacing) {
            if let symbol = appearance.symbol {
                Image(systemName: symbol)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(appearance.text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(appearance.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            appearance.color.opacity(0.12),
            in: Capsule(style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Charging service status: \(appearance.text)")
    }

    private var statusAppearance: (text: String, symbol: String?, color: Color) {
        switch presentation.status {
        case .checking:
            (String(localized: "Checking"), nil, .secondary)
        case .ready:
            (String(localized: "Ready"), "checkmark.circle.fill", .green)
        case .needsApproval:
            (
                String(localized: "Needs Approval"),
                "exclamationmark.triangle.fill",
                .orange
            )
        case .notInstalled:
            (String(localized: "Not Installed"), "xmark.circle", .secondary)
        case .connectionIssue:
            (
                String(localized: "Connection Issue"),
                "exclamationmark.circle.fill",
                .orange
            )
        }
    }
}
