import Defaults
import SwiftUI
import smc_power

struct ChargingSettingsView: View {
    @Default(.manageCharging) var manageCharging
    @Default(.chargeLimit) var chargeLimit
    @Default(.sailingMode) var sailingMode
    @Default(.sailingModeLimit) var sailingModeLimit
    @Default(.automaticDischarge) var automaticDischarge
    @Default(.disableSleepUntilChargeLimit) var disableSleepUntilChargeLimit
    @Default(.enableHeatProtectionMode) var enableHeatProtectionMode
    @Default(.heatProtectionLimit) var heatProtectionLimit
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @Default(.heatProtectionMagSafeLEDState) var heatProtectionMagSafeLEDState
    @State private var helperManager = ChargingDaemonManager.shared
    @State private var chargingController = ChargingManagementController()

    private let capabilities: DeviceCapabilities
    private let previewState: ChargingSettingsPreviewState?

    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
        self.previewState = nil
    }

    fileprivate init(
        capabilities: DeviceCapabilities,
        previewState: ChargingSettingsPreviewState
    ) {
        self.capabilities = capabilities
        self.previewState = previewState
    }

    private var hasChargingControl: Bool {
        capabilities.chargingControl
    }

    private var hasAdapterControl: Bool {
        capabilities.adapterControl
    }

    private var hasMagSafe: Bool {
        capabilities.hasMagSafe
    }

    private var hasAnyControl: Bool {
        hasChargingControl || hasAdapterControl
    }

    private var sailingResumePercentage: Int {
        chargeLimit - sailingModeLimit
    }

    private var helperStatus: ChargingHelperStatus {
        previewState?.helperStatus ?? helperManager.helperStatus
    }

    private var connectionStatus: ChargingDaemonConnectionStatus {
        previewState?.connectionStatus ?? helperManager.connectionStatus
    }

    private var isManageChargingOn: Bool {
        guard hasAnyControl else { return false }
        return previewState?.manageCharging ?? manageCharging
    }

    private var automaticDischargeBinding: Binding<Bool> {
        Binding(
            get: { hasAdapterControl && automaticDischarge },
            set: { automaticDischarge = hasAdapterControl ? $0 : false }
        )
    }

    private var sailingModeBinding: Binding<Bool> {
        Binding(
            get: { hasChargingControl && sailingMode },
            set: { sailingMode = hasChargingControl ? $0 : false }
        )
    }

    private var heatProtectionModeBinding: Binding<Bool> {
        Binding(
            get: { hasChargingControl && enableHeatProtectionMode },
            set: { enableHeatProtectionMode = hasChargingControl ? $0 : false }
        )
    }

    private var magSafeLEDBinding: Binding<Bool> {
        Binding(
            get: { capabilities.magsafeLEDControl && manageMagSafeLED },
            set: { manageMagSafeLED = capabilities.magsafeLEDControl ? $0 : false }
        )
    }

    private var isCheckingChargingDaemon: Bool {
        previewState?.isVerifying ?? chargingController.flowState.isLoading
    }

    private var displayedChargingControlError: String? {
        previewState?.errorMessage ?? chargingController.flowState.message
    }

    private var setupStatusMessage: String? {
        isCheckingChargingDaemon ? displayedChargingControlError : nil
    }

    private var displayedStatusMessage: String? {
        setupStatusMessage ?? displayedChargingControlError
    }

    private var shouldShowChargingControlError: Bool {
        guard displayedStatusMessage != nil else { return false }
        if helperStatus == .requiresApproval { return false }
        return true
    }

    private var shouldShowApprovalPrompt: Bool {
        guard helperStatus == .requiresApproval else { return false }
        if previewState != nil { return true }
        return chargingController.flowState.showsApprovalPrompt
    }

    private var isChargingDaemonReady: Bool {
        helperStatus == .installed
            && connectionStatus == .connected
            && !isCheckingChargingDaemon
    }

    private var shouldShowChargingControls: Bool {
        // Hide all dependent settings until the helper is installed, approved,
        // connected, and the persisted manage-charging flag is actually on.
        isManageChargingOn && isChargingDaemonReady
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Manage charging",
                    isOn: Binding(
                        get: { isManageChargingOn },
                        set: { newValue in
                            guard previewState == nil else { return }
                            toggleManageCharging(newValue)
                        }
                    )
                )
                .disabled(!hasAnyControl || isCheckingChargingDaemon)

                if !hasAnyControl {
                    UnsupportedCapabilityMessage(
                        title: Text("Charge management is unavailable on this Mac."),
                        message: Text("Stasis can still monitor battery status, but this hardware does not expose charging or adapter controls.")
                    )
                }

                if shouldShowApprovalPrompt {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("Open Login Items", systemImage: "gear") {
                                guard previewState == nil else { return }
                                openApprovalSettings()
                            }

                            Button("Check Again", systemImage: "arrow.clockwise") {
                                guard previewState == nil else { return }
                                checkApprovalStatus()
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Approve Stasis in Login Items to enable charge management.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let displayedStatusMessage, shouldShowChargingControlError {
                    ChargingDaemonStatusRow(
                        message: displayedStatusMessage,
                        isLoading: isCheckingChargingDaemon,
                        helperStatus: helperStatus,
                        connectionStatus: connectionStatus,
                        install: {
                            guard previewState == nil else { return }
                            requestEnableChargingManagement()
                        },
                        openApprovalSettings: {
                            guard previewState == nil else { return }
                            openApprovalSettings()
                        },
                        retry: {
                            guard previewState == nil else { return }
                            requestEnableChargingManagement()
                        },
                        reconnect: {
                            guard previewState == nil else { return }
                            reconnectChargingDaemon()
                        }
                    )
                }

                if shouldShowChargingControls {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(chargeLimit) },
                                    set: { chargeLimit = Int($0) }
                                ), in: 50...100, step: 5
                            )
                            Text("\(chargeLimit)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    } label: {
                        Text("Charge limit")
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charge Management")
                    Text("Limit the maximum charge level to extend battery lifespan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if shouldShowChargingControls {
                Section {
                    Toggle("Automatic discharge", isOn: automaticDischargeBinding)
                        .disabled(!hasAdapterControl)

                    if !hasAdapterControl {
                        UnsupportedCapabilityMessage(
                            title: Text("Adapter control is not supported on this device."),
                            message: Text("Automatic discharge requires adapter control support from this Mac.")
                        )
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Discharge")
                        Text(
                            "Discharge the battery to your charge limit when plugged in above the target level."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Disable sleep until charge limit", isOn: $disableSleepUntilChargeLimit)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Prevention")
                        Text(
                            "Prevent your Mac from sleeping while charging towards the charge limit. Sleep is re-enabled once the limit is reached or the adapter is disconnected."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Enable sailing mode", isOn: sailingModeBinding)
                        .disabled(!hasChargingControl)

                    if !hasChargingControl {
                        UnsupportedCapabilityMessage(
                            title: Text("Charging control is not supported on this device."),
                            message: Text("Sailing mode requires charging control support from this Mac.")
                        )
                    }

                    if hasChargingControl && sailingMode {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(sailingModeLimit) },
                                        set: { sailingModeLimit = Int($0) }
                                    ), in: 1...20, step: 1
                                )
                                Text("\(sailingModeLimit)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            Text("Threshold below limit")
                        }

                        LabeledContent("Charging resumes at") {
                            Text("\(sailingResumePercentage)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sailing Mode")
                        Text(
                            "Automatically resume charging when the battery drops below the threshold relative to your charge limit."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Enable heat protection", isOn: heatProtectionModeBinding)
                        .disabled(!hasChargingControl)

                    if !hasChargingControl {
                        UnsupportedCapabilityMessage(
                            title: Text("Charging control is not supported on this device."),
                            message: Text("Heat protection requires charging control support from this Mac.")
                        )
                    }

                    if hasChargingControl && enableHeatProtectionMode {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(heatProtectionLimit) },
                                        set: { heatProtectionLimit = Int($0) }
                                    ), in: 30...50, step: 1
                                )
                                Text("\(heatProtectionLimit)°C")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            Text("Temperature limit")
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Heat Protection")
                        Text("Pause charging when the battery temperature exceeds the threshold.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if hasMagSafe {
                    Section {
                        Toggle("Manage MagSafe LED", isOn: magSafeLEDBinding)
                            .disabled(!capabilities.magsafeLEDControl)

                        if !capabilities.magsafeLEDControl {
                            UnsupportedCapabilityMessage(
                                title: Text("MagSafe LED control is not supported on this device."),
                                message: Text("Stasis can still manage charging, but this Mac does not expose MagSafe LED controls.")
                            )
                        }

                        if capabilities.magsafeLEDControl && manageMagSafeLED {
                            if hasChargingControl && enableHeatProtectionMode {
                                Picker(
                                    "LED during heat protection",
                                    selection: $heatProtectionMagSafeLEDState
                                ) {
                                    Text("Off").tag(MagSafeLEDState.off)
                                    Text("Green").tag(MagSafeLEDState.green)
                                    Text("Orange").tag(MagSafeLEDState.orange)
                                    Text("Blinking Orange Slow").tag(MagSafeLEDState.blinkOrangeSlow)
                                    Text("Blinking Orange Fast").tag(MagSafeLEDState.blinkOrangeFast)
                                }
                            }
                        }
                    } header: {
                        Text("MagSafe LED Control")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
        .animation(.default, value: isManageChargingOn)
        .animation(.default, value: sailingMode)
        .animation(.default, value: enableHeatProtectionMode)
        .animation(.default, value: manageMagSafeLED)
        .animation(.default, value: helperStatus)
        .animation(.default, value: connectionStatus)
        .onAppear {
            guard previewState == nil else { return }
            resetUnsupportedSettings()
            chargingController.reconcileOnAppear(
                hasAnyControl: hasAnyControl,
                manageCharging: manageCharging,
                setManageCharging: { manageCharging = $0 }
            )
        }
        .onDisappear {
            guard previewState == nil else { return }
            chargingController.cancelPendingWork()
        }
        .onChange(of: helperManager.helperStatus) { _, newStatus in
            guard previewState == nil else { return }
            chargingController.handleHelperStatusChange(
                newStatus,
                setManageCharging: { manageCharging = $0 }
            )
        }
        .onChange(of: helperManager.connectionStatus) { _, newStatus in
            guard previewState == nil else { return }
            chargingController.handleConnectionStatusChange(
                newStatus,
                manageCharging: manageCharging,
                setManageCharging: { manageCharging = $0 }
            )
        }
    }

    private func toggleManageCharging(_ enabled: Bool) {
        if enabled {
            chargingController.requestEnable(
                hasAnyControl: hasAnyControl,
                setManageCharging: { manageCharging = $0 }
            )
        } else {
            chargingController.disable(setManageCharging: { manageCharging = $0 })
        }
    }

    private func checkApprovalStatus() {
        chargingController.checkApprovalStatus(
            setManageCharging: { manageCharging = $0 }
        )
    }

    private func openApprovalSettings() {
        chargingController.openApprovalSettings()
    }

    private func requestEnableChargingManagement() {
        chargingController.requestEnable(
            hasAnyControl: hasAnyControl,
            setManageCharging: { manageCharging = $0 }
        )
    }

    private func reconnectChargingDaemon() {
        helperManager.disconnect()
        requestEnableChargingManagement()
    }

    private func resetUnsupportedSettings() {
        if !hasAnyControl {
            manageCharging = false
        }
        if !hasAdapterControl {
            automaticDischarge = false
        }
        if !hasChargingControl {
            sailingMode = false
            enableHeatProtectionMode = false
        }
        if !capabilities.magsafeLEDControl {
            manageMagSafeLED = false
        }
    }
}

private struct UnsupportedCapabilityMessage: View {
    let title: Text
    let message: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
           title
                .font(.subheadline)
            message
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChargingDaemonStatusRow: View {
    let message: String
    let isLoading: Bool
    let helperStatus: ChargingHelperStatus
    let connectionStatus: ChargingDaemonConnectionStatus
    let install: () -> Void
    let openApprovalSettings: () -> Void
    let retry: () -> Void
    let reconnect: () -> Void

    var body: some View {
        LabeledContent {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                recoveryAction
            }
        } label: {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recoveryAction: some View {
        switch helperStatus {
        case .notInstalled:
            Button("Install Helper", systemImage: "wrench.and.screwdriver") {
                install()
            }
        case .requiresApproval:
            Button("Open Login Items", systemImage: "gear") {
                openApprovalSettings()
            }
        case .installed:
            switch connectionStatus {
            case .startupFailed:
                Button("Try Again", systemImage: "arrow.clockwise") {
                    retry()
                }
            case .runtimeFailed, .interrupted, .invalidated, .disconnected:
                Button("Reconnect", systemImage: "arrow.clockwise") {
                    reconnect()
                }
            case .connecting:
                EmptyView()
            case .connected:
                Button("Retry", systemImage: "arrow.clockwise") {
                    retry()
                }
            }
        }
    }
}

fileprivate struct ChargingSettingsPreviewState {
    let title: String
    let helperStatus: ChargingHelperStatus
    let connectionStatus: ChargingDaemonConnectionStatus
    let manageCharging: Bool
    let isVerifying: Bool
    let errorMessage: String?
}

private extension DeviceCapabilities {
    static let chargingSettingsPreview = DeviceCapabilities(
        chargingControl: true,
        adapterControl: true,
        hasMagSafe: true,
        magsafeLEDControl: true
    )

    static let chargingSettingsAdapterUnsupportedPreview = DeviceCapabilities(
        chargingControl: true,
        adapterControl: false,
        hasMagSafe: true,
        magsafeLEDControl: true
    )

    static let chargingSettingsChargingUnsupportedPreview = DeviceCapabilities(
        chargingControl: false,
        adapterControl: true,
        hasMagSafe: true,
        magsafeLEDControl: true
    )

    static let chargingSettingsMagSafeLEDUnsupportedPreview = DeviceCapabilities(
        chargingControl: true,
        adapterControl: true,
        hasMagSafe: true,
        magsafeLEDControl: false
    )
}

private struct ChargingSettingsPreviewContainer: View {
    let state: ChargingSettingsPreviewState
    var capabilities: DeviceCapabilities = .chargingSettingsPreview

    var body: some View {
        ChargingSettingsView(
            capabilities: capabilities,
            previewState: state
        )
        .frame(width: 520, height: 680)
    }
}

#Preview("Ready") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Ready",
            helperStatus: .installed,
            connectionStatus: .connected,
            manageCharging: true,
            isVerifying: false,
            errorMessage: nil
        )
    )
}

#Preview("Checking Helper") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Checking Helper",
            helperStatus: .installed,
            connectionStatus: .connecting,
            manageCharging: false,
            isVerifying: true,
            errorMessage: nil
        )
    )
}

#Preview("Requires Approval") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Requires Approval",
            helperStatus: .requiresApproval,
            connectionStatus: .disconnected,
            manageCharging: false,
            isVerifying: false,
            errorMessage: "Approve Stasis in System Settings to enable charge management."
        )
    )
}

#Preview("Setting Up Helper") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Setting Up Helper",
            helperStatus: .notInstalled,
            connectionStatus: .disconnected,
            manageCharging: false,
            isVerifying: true,
            errorMessage: nil
        )
    )
}

#Preview("Startup Failed") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Startup Failed",
            helperStatus: .installed,
            connectionStatus: .startupFailed("Charging daemon did not respond while verify charging daemon."),
            manageCharging: false,
            isVerifying: false,
            errorMessage: "Charging daemon did not respond while verify charging daemon."
        )
    )
}

#Preview("Runtime Interrupted") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Runtime Interrupted",
            helperStatus: .installed,
            connectionStatus: .interrupted,
            manageCharging: false,
            isVerifying: false,
            errorMessage: "Charging daemon connection was interrupted."
        )
    )
}

#Preview("Runtime Failed") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Runtime Failed",
            helperStatus: .installed,
            connectionStatus: .runtimeFailed("Charging daemon did not respond while manage battery charging."),
            manageCharging: false,
            isVerifying: false,
            errorMessage: "Charging daemon did not respond while manage battery charging."
        )
    )
}

#Preview("Adapter Unsupported") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Adapter Unsupported",
            helperStatus: .installed,
            connectionStatus: .connected,
            manageCharging: true,
            isVerifying: false,
            errorMessage: nil
        ),
        capabilities: .chargingSettingsAdapterUnsupportedPreview
    )
}

#Preview("Charging Unsupported") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "Charging Unsupported",
            helperStatus: .installed,
            connectionStatus: .connected,
            manageCharging: true,
            isVerifying: false,
            errorMessage: nil
        ),
        capabilities: .chargingSettingsChargingUnsupportedPreview
    )
}

#Preview("MagSafe LED Unsupported") {
    ChargingSettingsPreviewContainer(
        state: ChargingSettingsPreviewState(
            title: "MagSafe LED Unsupported",
            helperStatus: .installed,
            connectionStatus: .connected,
            manageCharging: true,
            isVerifying: false,
            errorMessage: nil
        ),
        capabilities: .chargingSettingsMagSafeLEDUnsupportedPreview
    )
}

#Preview("Unsupported") {
    ChargingSettingsView(
        capabilities: DeviceCapabilities(
            chargingControl: false,
            adapterControl: false,
            hasMagSafe: false,
            magsafeLEDControl: false
        )
    )
    .frame(width: 520, height: 420)
}
