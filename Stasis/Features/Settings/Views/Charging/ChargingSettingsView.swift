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

    /// True when the macOS 27-era firmware enforces the charge limit itself.
    /// Features the daemon cannot drive in that mode are described as
    /// mode-limited instead of missing hardware.
    private var isFirmwareChargeControl: Bool {
        settingsModel.capabilities?.firmwareChargeLimitControl == true
    }

    private var displayState: ChargingSettingsDisplayState {
        if let previewState {
            return ChargingSettingsDisplayState(
                previewState: previewState,
                hasAnyControl: hasAnyControl
            )
        }
        return ChargingSettingsDisplayState(
            daemonManager: daemonManager,
            chargingController: chargingController,
            settingsModel: settingsModel,
            hasAnyControl: hasAnyControl
        )
    }

    private var actions: ChargingSettingsActions {
        guard previewState == nil else { return .disabled }
        return ChargingSettingsActions(
            setManageCharging: toggleManageCharging,
            openApprovalSettings: chargingController.openApprovalSettings,
            checkApprovalStatus: checkApprovalStatus,
            requestEnableChargingManagement: requestEnableChargingManagement,
            reconnectChargingDaemon: reconnectChargingDaemon,
            requestUninstall: showUninstallConfirmation
        )
    }

    private var isChargingDaemonReady: Bool {
        displayState.daemonStatus == .installed
            && displayState.connectionStatus == .connected
            && settingsModel.managementState.settings != nil
            && capabilitiesResolved
            && !chargingController.isLoading
    }

    private var shouldShowChargingControls: Bool {
        displayState.isManageChargingOn && isChargingDaemonReady
    }

    var body: some View {
        let state = displayState

        Form {
            SettingsPageHeader(
                title: "Charging",
                message:
                    "Manage charging, battery protection, and MagSafe LED behavior."
            )

            ChargingManagementSection(
                managementState: settingsModel.managementState,
                thresholdState: settingsModel.thresholdState,
                hasAnyControl: hasAnyControl,
                shouldShowChargingControls: shouldShowChargingControls,
                state: state,
                actions: actions
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
                    hasChargingControl: heatProtectionSupported,
                    isModeLimited: isFirmwareChargeControl
                )

                if hasMagSafe {
                    ChargingMagSafeLEDSection(
                        state: settingsModel.magSafeLEDState,
                        heatProtectionState: settingsModel.heatProtectionState,
                        hasChargingControl: heatProtectionSupported,
                        hasMagSafeLEDControl: magSafeLEDSupported,
                        isModeLimited: isFirmwareChargeControl
                    )
                }
            }
        }
        .settingsFormLayout()
        .disabled(previewState == nil && state.isUninstalling)
        .animation(.default, value: state)
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
