import SwiftUI

struct ChargeLimitOverrideToggleView: View {
    let chargingCoordinator: ChargingCoordinator

    var body: some View {
        HStack {
            Text("Charge Limit Override")
            Spacer(minLength: 20)
            Toggle(
                "Charge Limit Override",
                isOn: Binding(
                    get: { chargingCoordinator.chargeLimitOverrideActive },
                    set: { _ in chargingCoordinator.toggleChargeLimitOverride() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(chargingCoordinator.forceDischargeActive)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

struct ForceDischargeToggleView: View {
    let chargingCoordinator: ChargingCoordinator

    var body: some View {
        HStack {
            Text("Force Discharge")
            Spacer(minLength: 20)
            Toggle(
                "Force Discharge",
                isOn: Binding(
                    get: { chargingCoordinator.forceDischargeActive },
                    set: { _ in chargingCoordinator.toggleForceDischarge() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(chargingCoordinator.chargeLimitOverrideActive)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}
