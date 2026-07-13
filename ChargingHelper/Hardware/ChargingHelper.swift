import Foundation
import os.log
import smc_power

actor ChargingHelper: DaemonHardwareControlling {
  private let battery: SMCBattery
  private let adapter: SMCAdapter
  private let logger = Logger(
    subsystem: "com.srimanachanta.stasis-daemon",
    category: "ChargingHardware"
  )

  init(battery: SMCBattery, adapter: SMCAdapter) {
    self.battery = battery
    self.adapter = adapter
    logger.info(
      "Initialized (mode=\(battery.capabilities.chargeControlMode.rawValue), charging=\(battery.capabilities.inhibitChargeControl), adapter=\(adapter.capabilities.powerControl), magSafe=\(adapter.capabilities.magSafeControl))"
    )
  }

  func setChargingEnabled(_ enabled: Bool) throws {
    guard battery.capabilities.inhibitChargeControl else {
      throw SMCBatteryError.unsupportedCapability
    }
    let currentlyInhibited = try battery.getChargingInhibited()
    if currentlyInhibited != !enabled {
      try battery.setChargingInhibited(!enabled)
      logger.debug("SMC set charging enabled to: \(enabled)")
    }
  }

  func setAdapterEnabled(_ enabled: Bool) throws {
    guard adapter.capabilities.powerControl else {
      throw SMCAdapterError.powerControlNotSupported
    }
    if try adapter.ensurePowerEnabled(enabled) {
      logger.debug("SMC set adapter power enabled to: \(enabled)")
    }
  }

  func setMagSafeLED(rawValue: UInt8) throws {
    guard adapter.capabilities.magSafeControl else {
      throw SMCAdapterError.magSafeNotSupported
    }
    guard let state = MagSafeLEDState(rawValue: rawValue) else {
      throw SMCAdapterError.unknownLEDState(rawValue)
    }
    let currentState = try adapter.getMagSafeLEDState()
    if currentState != state {
      try adapter.setMagSafeLEDState(state)
      logger.debug("SMC MagSafe LED set to: \(state.rawValue)")
    }
  }

  func readHardwareState() throws -> DaemonHardwareState {
    let mode = battery.capabilities.chargeControlMode
    let chargingInhibited =
      mode == .legacy ? try battery.getChargingInhibited() : nil
    let firmwareState: DaemonFirmwareChargeLimitState?
    if mode == .firmware {
      let state = try battery.getFirmwareChargeLimit()
      firmwareState = DaemonFirmwareChargeLimitState(
        active: state.active,
        lower: Int(state.lower),
        upper: Int(state.upper)
      )
    } else {
      firmwareState = nil
    }

    let forceDischarging =
      adapter.capabilities.powerControl ? try !adapter.getPowerEnabled() : nil
    let ledRawValue =
      adapter.capabilities.magSafeControl ? try adapter.getMagSafeLEDState().rawValue : nil

    return DaemonHardwareState(
      chargingInhibited: chargingInhibited,
      forceDischarging: forceDischarging,
      magSafeLEDStateRawValue: ledRawValue,
      firmwareChargeLimit: firmwareState
    )
  }

  func resetToDefaults() {
    do {
      if battery.capabilities.inhibitChargeControl {
        try battery.setChargingEnabled(true)
      }
      if adapter.capabilities.powerControl {
        try adapter.setPowerEnabled(true)
      }
      if adapter.capabilities.magSafeControl {
        try adapter.setMagSafeLEDState(.reset)
      }
      logger.info("SMC keys reset to defaults")
    } catch {
      logger.error("resetToDefaults failed: \(error.localizedDescription)")
    }
  }
}
