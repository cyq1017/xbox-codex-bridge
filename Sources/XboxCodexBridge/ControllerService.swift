import CoreHaptics
import Foundation
import GameController
import XboxCodexBridgeCore

struct ControllerCapabilities {
  let connected: Bool
  let name: String?
  let hasHaptics: Bool
  let hasLight: Bool
  let hasShareButton: Bool
}

protocol ControllerSystemGestureInput: AnyObject {
  var preferredSystemGestureState: GCControllerElement.SystemGestureState { get set }
}

extension GCControllerButtonInput: ControllerSystemGestureInput {}

enum ControllerSystemGesturePolicy {
  static func claim(_ input: ControllerSystemGestureInput?) {
    input?.preferredSystemGestureState = .disabled
  }
}

enum ControllerHapticLocalityPolicy {
  static func preferredLocality(
    supportedLocalities: Set<GCHapticsLocality>
  ) -> GCHapticsLocality {
    supportedLocalities.contains(.all) ? .all : .default
  }
}

final class ControllerService {
  var onControl: ((GamepadControl, Bool) -> Void)?
  var onStick: ((Bool, Float, Float) -> Void)?
  var onCapabilities: ((ControllerCapabilities) -> Void)?

  private var controller: GCController?
  private var observers: [NSObjectProtocol] = []
  private var hapticEngine: CHHapticEngine?

  func start() {
    GCController.shouldMonitorBackgroundEvents = true
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: .GCControllerDidConnect,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let controller = notification.object as? GCController else { return }
        self?.configure(controller)
      })
    observers.append(
      center.addObserver(
        forName: .GCControllerDidDisconnect,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let self, let disconnected = notification.object as? GCController else { return }
        if self.controller === disconnected {
          self.controller = nil
          self.hapticEngine = nil
          self.publishCapabilities()
        }
      })

    if let existing = GCController.controllers().first {
      configure(existing)
    }
    GCController.startWirelessControllerDiscovery(completionHandler: nil)
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    GCController.stopWirelessControllerDiscovery()
  }

  @discardableResult
  func testLight(red: Float, green: Float, blue: Float) -> Bool {
    onMain {
      guard let light = controller?.light else { return false }
      light.color = GCColor(
        red: min(max(red, 0), 1),
        green: min(max(green, 0), 1),
        blue: min(max(blue, 0), 1)
      )
      return true
    }
  }

  @discardableResult
  func testHaptic() -> Bool {
    playHaptic(pulses: [HapticPatternLibrary.manualConfirmationPulse])
  }

  @discardableResult
  func playHaptic(_ kind: HapticFeedbackKind) -> Bool {
    playHaptic(pulses: HapticPatternLibrary.pulses(for: kind))
  }

  private func playHaptic(pulses: [HapticPulse]) -> Bool {
    onMain {
      guard let haptics = controller?.haptics else {
        return false
      }
      let locality = ControllerHapticLocalityPolicy.preferredLocality(
        supportedLocalities: haptics.supportedLocalities
      )
      guard let engine = haptics.createEngine(withLocality: locality)
      else {
        return false
      }
      do {
        hapticEngine?.stop(completionHandler: nil)
        try engine.start()
        let events = pulses.map { pulse in
          CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
              CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity),
              CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness),
            ],
            relativeTime: pulse.relativeTime,
            duration: pulse.duration
          )
        }
        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
        hapticEngine = engine
        let totalDuration = pulses.map { $0.relativeTime + $0.duration }.max() ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.1) { [weak self] in
          self?.hapticEngine?.stop(completionHandler: nil)
          self?.hapticEngine = nil
        }
        return true
      } catch {
        hapticEngine = nil
        return false
      }
    }
  }

  private func configure(_ controller: GCController) {
    guard let gamepad = controller.extendedGamepad else { return }
    self.controller = controller

    bind(gamepad.buttonA, to: .a)
    bind(gamepad.buttonB, to: .b)
    bind(gamepad.buttonX, to: .x)
    bind(gamepad.buttonY, to: .y)
    bind(gamepad.leftShoulder, to: .lb)
    bind(gamepad.rightShoulder, to: .rb)
    bind(gamepad.leftTrigger, to: .lt, asAnalogTrigger: true)
    bind(gamepad.rightTrigger, to: .rt, asAnalogTrigger: true)
    bind(gamepad.leftThumbstickButton, to: .l3)
    bind(gamepad.rightThumbstickButton, to: .r3)
    bind(gamepad.buttonMenu, to: .menu)
    ControllerSystemGesturePolicy.claim(gamepad.buttonOptions)
    bind(gamepad.buttonOptions, to: .view)
    ControllerSystemGesturePolicy.claim(gamepad.buttonHome)
    bind(gamepad.buttonHome, to: .home)
    bind(gamepad.dpad.up, to: .dpadUp)
    bind(gamepad.dpad.right, to: .dpadRight)
    bind(gamepad.dpad.down, to: .dpadDown)
    bind(gamepad.dpad.left, to: .dpadLeft)

    if let xbox = gamepad as? GCXboxGamepad, let share = xbox.buttonShare {
      share.preferredSystemGestureState = .disabled
      bind(share, to: .share)
    }

    gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
      self?.emitStick(isLeft: true, x: x, y: y)
    }
    gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
      self?.emitStick(isLeft: false, x: x, y: y)
    }
    publishCapabilities()
  }

  private func bind(
    _ input: GCControllerButtonInput?,
    to control: GamepadControl,
    asAnalogTrigger: Bool = false
  ) {
    if asAnalogTrigger {
      var gate = TriggerPressGate()
      input?.valueChangedHandler = { [weak self] _, value, _ in
        guard let transition = gate.update(value: value) else { return }
        self?.emitControl(control, isPressed: transition == .pressed)
      }
      return
    }
    input?.pressedChangedHandler = { [weak self] _, _, isPressed in
      self?.emitControl(control, isPressed: isPressed)
    }
  }

  private func emitControl(_ control: GamepadControl, isPressed: Bool) {
    if Thread.isMainThread {
      onControl?(control, isPressed)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.onControl?(control, isPressed)
      }
    }
  }

  private func emitStick(isLeft: Bool, x: Float, y: Float) {
    if Thread.isMainThread {
      onStick?(isLeft, x, y)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.onStick?(isLeft, x, y)
      }
    }
  }

  private func publishCapabilities() {
    let xbox = controller?.extendedGamepad as? GCXboxGamepad
    onCapabilities?(
      ControllerCapabilities(
        connected: controller != nil,
        name: controller?.vendorName ?? controller?.productCategory,
        hasHaptics: controller?.haptics != nil,
        hasLight: controller?.light != nil,
        hasShareButton: xbox?.buttonShare != nil
      ))
  }

  private func onMain<T>(_ operation: () -> T) -> T {
    if Thread.isMainThread { return operation() }
    return DispatchQueue.main.sync(execute: operation)
  }
}
