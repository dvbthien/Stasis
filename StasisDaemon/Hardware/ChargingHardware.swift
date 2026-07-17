import Foundation
import os.log
import smc_power

actor ChargingHardware: DaemonHardwareControlling {
  private let battery: SMCBattery
  private let adapter: SMCAdapter
  private let logger = Logger(
    subsystem: Constants.Identity.daemon,
    category: "ChargingHardware"
  )

  init(battery: SMCBattery, adapter: SMCAdapter) {
    self.battery = battery
    self.adapter = adapter
    logger.info(
      "Initialized (mode=\(battery.capabilities.chargeControlMode.rawValue), charging=\(battery.capabilities.inhibitChargeControl), adapter=\(adapter.capabilities.powerControl), magSafe=\(adapter.capabilities.magSafeControl))"
    )
  }

  func setChargingEnabled(_ enabled: Bool) throws -> Bool {
    guard battery.capabilities.inhibitChargeControl else {
      throw SMCBatteryError.unsupportedCapability
    }
    let currentlyInhibited = try battery.getChargingInhibited()
    if currentlyInhibited != !enabled {
      try battery.setChargingInhibited(!enabled)
      logger.debug("SMC set charging enabled to: \(enabled)")
      return true
    }
    return false
  }

  func setAdapterEnabled(_ enabled: Bool) throws -> Bool {
    guard adapter.capabilities.powerControl else {
      throw SMCAdapterError.powerControlNotSupported
    }
    let changed = try adapter.ensurePowerEnabled(enabled)
    if changed {
      logger.debug("SMC set adapter power enabled to: \(enabled)")
    }
    return changed
  }

  func setMagSafeLED(rawValue: UInt8) throws -> Bool {
    guard adapter.capabilities.magSafeControl else {
      throw SMCAdapterError.magSafeNotSupported
    }
    guard MagSafeLEDState(rawValue: rawValue) != nil else {
      throw SMCAdapterError.unknownLEDState(rawValue)
    }
    let currentRawValue = try adapter.getMagSafeLEDStateRawValue()
    if currentRawValue != rawValue {
      try adapter.setMagSafeLEDStateRawValue(rawValue)
      logger.debug("SMC MagSafe LED set to: \(rawValue)")
      return true
    }
    return false
  }

  func ensureFirmwareChargeLimit(lower: Int, upper: Int) throws -> Bool {
    let changed = try battery.ensureFirmwareChargeLimit(lower: lower, upper: upper)
    if changed {
      logger.debug("SMC firmware charge limit set to lower=\(lower) upper=\(upper)")
    }
    return changed
  }

  func ensureFirmwareChargeLimitDisabled() throws -> Bool {
    let changed = try battery.ensureFirmwareChargeLimitDisabled()
    if changed {
      logger.debug("SMC firmware charge limit disabled")
    }
    return changed
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
      adapter.capabilities.magSafeControl ? try adapter.getMagSafeLEDStateRawValue() : nil

    return DaemonHardwareState(
      chargingInhibited: chargingInhibited,
      forceDischarging: forceDischarging,
      magSafeLEDStateRawValue: ledRawValue,
      firmwareChargeLimit: firmwareState
    )
  }

}
