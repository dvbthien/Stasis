import SwiftUI

struct ChargeLimitOverrideToggleView: View {
    let controls: ChargingTemporaryControlsModel

    var body: some View {
        HStack {
            Text("Charge Limit Override")
            Spacer(minLength: 20)
            Toggle(
                "Charge Limit Override",
                isOn: Binding(
                    get: { controls.chargeLimitOverrideActive },
                    set: { controls.setChargeLimitOverride($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(controls.forceDischargeActive)
        }
        .foregroundStyle(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

struct ForceDischargeToggleView: View {
    let controls: ChargingTemporaryControlsModel

    var body: some View {
        HStack {
            Text("Force Discharge")
            Spacer(minLength: 20)
            Toggle(
                "Force Discharge",
                isOn: Binding(
                    get: { controls.forceDischargeActive },
                    set: { controls.setForceDischarge($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(controls.chargeLimitOverrideActive)
        }
        .foregroundStyle(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}
