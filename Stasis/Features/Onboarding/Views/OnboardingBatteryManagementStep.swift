import SwiftUI

/// Guides the user through enabling charge management. Writes its own
/// presentation, but the enable/approve/retry logic is the same
/// `ChargingManagementController` + `ChargingDaemonManager.shared` singleton
/// the Charging settings tab drives, so state stays consistent between them.
struct OnboardingBatteryManagementStep: View {
    /// Called once, ~1s after the daemon reaches `.ready` while this step is
    /// visible, so onboarding can advance on its own.
    var onReady: () -> Void

    @State private var chargingSettingsModel = ChargingSettingsModel()
    @State private var chargingController = ChargingManagementController()
    @State private var daemonManager = ChargingDaemonManager.shared
    @State private var didAutoAdvance = false

    private var hasAnyControl: Bool {
        chargingSettingsModel.availability.canAttemptManagement
    }

    private var isManageChargingOn: Bool {
        hasAnyControl && (chargingSettingsModel.managementState.settings?.isEnabled ?? false)
    }

    private var manageChargingBinding: Binding<Bool> {
        Binding(
            get: { isManageChargingOn },
            set: { newValue in
                if newValue {
                    enable()
                } else {
                    chargingController.disable(
                        setManageCharging: { chargingSettingsModel.managementState.setEnabled($0) }
                    )
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                icon: "battery.100.bolt",
                title: "Battery Management",
                subtitle: "Stasis can limit how far your Mac charges to protect long-term battery health."
            )

            OnboardingToggleRow(
                title: "Manage charging",
                description: "Let Stasis automatically protect your battery's long-term health.",
                isOn: manageChargingBinding
            )
            .disabled(!hasAnyControl || chargingController.isLoading)

            statusCard

            Spacer()
        }
        .onAppear {
            chargingController.reconcileOnAppear(
                hasAnyControl: hasAnyControl,
                manageCharging: chargingSettingsModel.managementState.settings?.isEnabled == true
            )
        }
        .onDisappear {
            chargingController.cancelPendingWork()
        }
        .onChange(of: daemonManager.daemonStatus) { _, newStatus in
            chargingController.handleDaemonStatusChange(newStatus)
        }
        .onChange(of: daemonManager.connectionStatus) { _, newStatus in
            chargingController.handleConnectionStatusChange(
                newStatus,
                manageCharging: chargingSettingsModel.managementState.settings?.isEnabled == true
            )
        }
        .onChange(of: chargingController.flowState) { _, newState in
            guard newState == .ready, !didAutoAdvance else { return }
            didAutoAdvance = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                onReady()
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        if !hasAnyControl {
            OnboardingStatusCard(
                icon: "exclamationmark.triangle.fill",
                title: "Not available on this Mac",
                description: "This hardware doesn't expose charging controls, but Stasis can still monitor battery status.",
                tint: .orange
            )
        } else if chargingController.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(chargingController.flowState.message ?? "Working…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingSurface())
        } else if chargingController.flowState.showsApprovalPrompt {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingGuidancePanel(
                    title: "Approve Stasis in Login Items",
                    rows: [
                        "Open Login Items in System Settings.",
                        "Turn on Stasis in the background-services list.",
                        "Come back here and tap Check Again.",
                    ]
                )

                HStack(spacing: SettingsLayout.controlSpacing) {
                    Button("Open Login Items", systemImage: "gear") {
                        chargingController.openApprovalSettings()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    Button("Check Again", systemImage: "arrow.clockwise") {
                        checkApprovalStatus()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
        } else if case .failed(let message) = chargingController.flowState {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingStatusCard(
                    icon: "xmark.circle.fill",
                    title: "Couldn't enable battery management",
                    description: message,
                    tint: .red
                )

                Button("Try Again", systemImage: "arrow.clockwise", action: enable)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        } else {
            HStack(spacing: 10) {
                OnboardingHighlightCard(
                    icon: "gauge.with.dots.needle.50percent",
                    title: "Charge Limit",
                    subtitle: "Caps charging below 100%"
                )
                OnboardingHighlightCard(
                    icon: "wind",
                    title: "Sailing Mode",
                    subtitle: "Skips micro-charges near your limit"
                )
                OnboardingHighlightCard(
                    icon: "leaf.fill",
                    title: "Longer Lifespan",
                    subtitle: "Fewer full-charge cycles"
                )
            }
        }
    }

    private func enable() {
        chargingController.requestEnable(
            hasAnyControl: hasAnyControl,
            setManageCharging: { chargingSettingsModel.managementState.setEnabled($0) }
        )
    }

    private func checkApprovalStatus() {
        chargingController.checkApprovalStatus(
            hasAnyControl: hasAnyControl,
            setManageCharging: { chargingSettingsModel.managementState.setEnabled($0) }
        )
    }
}
