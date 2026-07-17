import SwiftUI

struct ChargingSettingsView: View {
    @State private var daemonManager = ChargingDaemonManager.shared
    @State private var chargingController = ChargingManagementController()
    @State private var showsUninstallConfirmation = false
    @Bindable var settingsModel: ChargingSettingsModel

    private let fallbackCapabilities: DeviceCapabilities
    private let previewState: ChargingSettingsPreviewState?

    init(
        capabilities: DeviceCapabilities,
        settingsModel: ChargingSettingsModel
    ) {
        fallbackCapabilities = capabilities
        previewState = nil
        self.settingsModel = settingsModel
    }

    init(
        capabilities: DeviceCapabilities,
        previewState: ChargingSettingsPreviewState
    ) {
        fallbackCapabilities = capabilities
        self.previewState = previewState
        settingsModel = ChargingSettingsModel.preview(
            managementEnabled: previewState.manageCharging
        )
    }

    private var hasChargingControl: Bool {
        settingsModel.capabilities?.chargingControl
            ?? fallbackCapabilities.chargingControl
    }

    private var hasAdapterControl: Bool {
        settingsModel.capabilities?.adapterControl
            ?? fallbackCapabilities.adapterControl
    }

    private var hasMagSafe: Bool {
        settingsModel.capabilities?.magSafeLEDKeyAvailable
            ?? fallbackCapabilities.hasMagSafe
    }

    private var hasAnyControl: Bool {
        if previewState == nil {
            return settingsModel.availability.canAttemptManagement
        }
        return fallbackCapabilities.chargingControl
            || fallbackCapabilities.adapterControl
    }

    private var capabilitiesResolved: Bool {
        previewState != nil || settingsModel.availability.isResolved
    }

    private var automaticDischargeSupported: Bool {
        settingsModel.capabilities?.automaticDischargeControl
            ?? (hasChargingControl && hasAdapterControl)
    }

    private var sailingModeSupported: Bool {
        settingsModel.capabilities?.sailingModeControl ?? hasChargingControl
    }

    private var sleepPreventionSupported: Bool {
        settingsModel.capabilities?.sleepHooks ?? hasChargingControl
    }

    private var heatProtectionSupported: Bool {
        settingsModel.capabilities?.heatProtectionControl ?? hasChargingControl
    }

    private var magSafeLEDSupported: Bool {
        settingsModel.capabilities?.magSafeLEDControl
            ?? fallbackCapabilities.magsafeLEDControl
    }

    private var daemonStatus: ChargingDaemonStatus {
        previewState?.daemonStatus ?? daemonManager.daemonStatus
    }

    private var connectionStatus: ChargingDaemonConnectionStatus {
        previewState?.connectionStatus ?? daemonManager.connectionStatus
    }

    private var isManageChargingOn: Bool {
        guard hasAnyControl else { return false }
        return previewState?.manageCharging ?? settingsModel.managementState
            .settings?.isEnabled ?? false
    }

    private var isCheckingChargingDaemon: Bool {
        previewState.map { $0.isVerifying || $0.isUninstalling }
            ?? (chargingController.isLoading
                || settingsModel.isSaving)
    }

    private var isDeterminingDaemonStatus: Bool {
        previewState?.isVerifying
            ?? chargingController.isDeterminingDaemonStatus
    }

    private var isUninstalling: Bool {
        previewState?.isUninstalling
            ?? (chargingController.flowState == .uninstalling)
    }

    private var uninstallErrorMessage: String? {
        previewState?.uninstallErrorMessage
            ?? chargingController.flowState.uninstallErrorMessage
    }

    private var displayedStatusMessage: String? {
        previewState?.errorMessage ?? chargingController.flowState.message
    }

    private var shouldShowApprovalPrompt: Bool {
        guard daemonStatus == .requiresApproval else { return false }
        return previewState != nil
            || chargingController.flowState.showsApprovalPrompt
    }

    private var isChargingDaemonReady: Bool {
        daemonStatus == .installed
            && connectionStatus == .connected
            && settingsModel.managementState.settings != nil
            && capabilitiesResolved
            && !chargingController.isLoading
    }

    private var shouldShowChargingControls: Bool {
        isManageChargingOn && isChargingDaemonReady
    }

    var body: some View {
        Form {
            SettingsPageHeader(
                title: "Charging",
                message:
                    "Manage charging, battery protection, and MagSafe LED behavior."
            )

            ChargingManagementSection(
                managementState: settingsModel.managementState,
                thresholdState: settingsModel.thresholdState,
                previewManageCharging: previewState?.manageCharging,
                hasAnyControl: hasAnyControl,
                shouldShowChargingControls: shouldShowChargingControls,
                isCheckingChargingDaemon: isCheckingChargingDaemon,
                isDeterminingDaemonStatus: isDeterminingDaemonStatus,
                isUninstalling: isUninstalling,
                shouldShowApprovalPrompt: shouldShowApprovalPrompt,
                displayedStatusMessage: displayedStatusMessage,
                uninstallErrorMessage: uninstallErrorMessage,
                daemonStatus: daemonStatus,
                connectionStatus: connectionStatus,
                setManageCharging: setManageCharging,
                openApprovalSettings: runPreviewSafe(openApprovalSettings),
                checkApprovalStatus: runPreviewSafe(checkApprovalStatus),
                requestEnableChargingManagement: runPreviewSafe(
                    requestEnableChargingManagement
                ),
                reconnectChargingDaemon: runPreviewSafe(reconnectChargingDaemon),
                requestUninstall: runPreviewSafe(showUninstallConfirmation)
            )

            if shouldShowChargingControls {
                ChargingDischargeSection(
                    state: settingsModel.automaticDischargeState,
                    isSupported: automaticDischargeSupported
                )

                ChargingSleepPreventionSection(
                    state: settingsModel.sleepPreventionState,
                    isSupported: sleepPreventionSupported
                )

                ChargingSailingModeSection(
                    state: settingsModel.thresholdState,
                    isSupported: sailingModeSupported
                )

                ChargingHeatProtectionSection(
                    state: settingsModel.heatProtectionState,
                    hasChargingControl: heatProtectionSupported
                )

                if hasMagSafe {
                    ChargingMagSafeLEDSection(
                        state: settingsModel.magSafeLEDState,
                        heatProtectionState: settingsModel.heatProtectionState,
                        hasChargingControl: heatProtectionSupported,
                        hasMagSafeLEDControl: magSafeLEDSupported
                    )
                }
            }
        }
        .settingsFormLayout()
        .disabled(previewState == nil && isUninstalling)
        .animation(.default, value: isManageChargingOn)
        .animation(.default, value: daemonStatus)
        .animation(.default, value: connectionStatus)
        .alert(
            "Remove Background Service?",
            isPresented: $showsUninstallConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                requestUninstall()
            }
        } message: {
            Text(
                "Charging management will stop, and your Mac’s charging controls will return to their default state. You can enable it again at any time."
            )
        }
        .onAppear {
            guard previewState == nil else { return }
            chargingController.reconcileOnAppear(
                hasAnyControl: hasAnyControl,
                manageCharging: settingsModel.managementState.settings?
                    .isEnabled == true
            )
        }
        .onDisappear {
            guard previewState == nil else { return }
            chargingController.cancelPendingWork()
        }
        .onChange(of: daemonManager.daemonStatus) { _, newStatus in
            guard previewState == nil else { return }
            chargingController.handleDaemonStatusChange(newStatus)
        }
        .onChange(of: daemonManager.connectionStatus) { _, newStatus in
            guard previewState == nil else { return }
            chargingController.handleConnectionStatusChange(
                newStatus,
                manageCharging: settingsModel.managementState.settings?
                    .isEnabled == true
            )
        }
    }

    private func setManageCharging(_ enabled: Bool) {
        guard previewState == nil else { return }
        toggleManageCharging(enabled)
    }

    private func runPreviewSafe(_ action: @escaping () -> Void) -> () -> Void {
        { if previewState == nil { action() } }
    }

    private func toggleManageCharging(_ enabled: Bool) {
        if enabled {
            requestEnableChargingManagement()
        } else {
            chargingController.disable(
                setManageCharging: {
                    settingsModel.managementState.setEnabled($0)
                }
            )
        }
    }

    private func checkApprovalStatus() {
        chargingController.checkApprovalStatus(
            hasAnyControl: hasAnyControl,
            setManageCharging: { settingsModel.managementState.setEnabled($0) }
        )
    }

    private func openApprovalSettings() {
        chargingController.openApprovalSettings()
    }

    private func requestEnableChargingManagement() {
        chargingController.requestEnable(
            hasAnyControl: hasAnyControl,
            setManageCharging: { settingsModel.managementState.setEnabled($0) }
        )
    }

    private func reconnectChargingDaemon() {
        daemonManager.disconnect()
        requestEnableChargingManagement()
    }

    private func showUninstallConfirmation() {
        showsUninstallConfirmation = true
    }

    private func requestUninstall() {
        chargingController.requestUninstall(settingsModel: settingsModel)
    }
}
