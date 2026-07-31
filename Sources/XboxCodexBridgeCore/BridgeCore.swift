import Foundation

public enum BridgeLayer: String, Codable, CaseIterable, Sendable {
  case base
  case task
  case developer
  case safety
  case system
}

public enum GamepadControl: String, Codable, CaseIterable, Hashable, Sendable {
  case a, b, x, y
  case lb, rb, lt, rt
  case l3, r3
  case dpadUp, dpadRight, dpadDown, dpadLeft
  case leftStickUp, leftStickRight, leftStickDown, leftStickLeft
  case rightStickUp, rightStickRight, rightStickDown, rightStickLeft
  case menu, view, share, home
}

public enum LayerResolver {
  public static func resolve(pressed: Set<GamepadControl>) -> BridgeLayer {
    if pressed.contains(.lb), pressed.contains(.rb) {
      return .safety
    }
    if pressed.contains(.rb) {
      return .developer
    }
    if pressed.contains(.lb) {
      return .task
    }
    if pressed.contains(.view) {
      return .system
    }
    return .base
  }
}

public enum ModelMenuNavigationAction: Equatable, Sendable {
  case up
  case down
  case enter
  case back
  case confirm
  case cancel
}

public enum ModelMenuActivationPlan {
  public static func initialNavigation(
    openAccepted: Bool
  ) -> ModelMenuNavigationAction? {
    openAccepted ? .down : nil
  }
}

public enum ModelMenuTransitionDecision: Equatable, Sendable {
  case ready
  case retry(after: TimeInterval)
  case finish
}

public enum ModelMenuTransitionPlan {
  public static func decision(
    hasVisibleItems: Bool,
    attempt: Int
  ) -> ModelMenuTransitionDecision {
    if hasVisibleItems { return .ready }
    if attempt < 5 { return .retry(after: 0.10) }
    return .finish
  }
}

public enum ModifierChordResolution: Equatable, Sendable {
  case deferBaseA
  case dispatchA(BridgeLayer)
}

public enum OverlayInputTarget: Equatable, Sendable {
  case windowSwitcher
  case modelMenu
  case mapping
}

public enum OverlayInputPriority {
  public static func resolve(
    windowSwitcherIsPresented: Bool,
    modelMenuIsActive: Bool
  ) -> OverlayInputTarget {
    if windowSwitcherIsPresented { return .windowSwitcher }
    if modelMenuIsActive { return .modelMenu }
    return .mapping
  }
}

public enum ModelPickerChordDecision: Equatable, Sendable {
  case reopen
  case deferMenuA
  case passthrough
}

public enum ModelPickerChordPlan {
  public static func decision(
    control: GamepadControl,
    isPressed: Bool,
    pressed: Set<GamepadControl>,
    modelMenuIsActive: Bool
  ) -> ModelPickerChordDecision {
    guard modelMenuIsActive, isPressed else { return .passthrough }
    if (control == .a || control == .rb), pressed.contains(.a), pressed.contains(.rb),
      !pressed.contains(.lb)
    {
      return .reopen
    }
    return control == .a ? .deferMenuA : .passthrough
  }
}

/// Keeps a face-button press briefly pending so Bluetooth event ordering cannot
/// turn an intended modifier chord into a base-layer action.
public struct ModifierChordState: Sendable {
  private var hasPendingBaseA = false

  public init() {}

  public mutating func handle(
    control: GamepadControl,
    isPressed: Bool,
    pressed: Set<GamepadControl>
  ) -> ModifierChordResolution? {
    guard isPressed else { return nil }

    if control == .a {
      let layer = LayerResolver.resolve(pressed: pressed)
      if layer == .base {
        hasPendingBaseA = true
        return .deferBaseA
      }
      return nil
    }

    guard hasPendingBaseA, pressed.contains(.a),
      control == .lb || control == .rb || control == .view
    else { return nil }

    hasPendingBaseA = false
    return .dispatchA(LayerResolver.resolve(pressed: pressed))
  }

  public mutating func consumeDeferredBaseA() -> ModifierChordResolution? {
    guard hasPendingBaseA else { return nil }
    hasPendingBaseA = false
    return .dispatchA(.base)
  }
}

public enum SafetyYChordResolution: Equatable, Sendable {
  case deferY
  case dispatchY(BridgeLayer)
}

/// Keeps Y pending briefly so a Bluetooth event-order race cannot turn an
/// intended LB+RB+Y safety chord into a base/task/developer Y action.
public struct SafetyYChordState: Sendable {
  private var pendingLayer: BridgeLayer?

  public init() {}

  public mutating func handle(
    control: GamepadControl,
    isPressed: Bool,
    pressed: Set<GamepadControl>
  ) -> SafetyYChordResolution? {
    guard isPressed else { return nil }

    if control == .y {
      let layer = LayerResolver.resolve(pressed: pressed)
      guard layer != .safety else {
        pendingLayer = nil
        return nil
      }
      pendingLayer = layer
      return .deferY
    }

    guard pendingLayer != nil,
      pressed.contains(.y),
      control == .lb || control == .rb,
      LayerResolver.resolve(pressed: pressed) == .safety
    else { return nil }

    pendingLayer = nil
    return .dispatchY(.safety)
  }

  public mutating func consumeDeferredY() -> SafetyYChordResolution? {
    guard let layer = pendingLayer else { return nil }
    pendingLayer = nil
    return .dispatchY(layer)
  }
}

public struct ModelMenuNavigationState: Sendable {
  public private(set) var isActive = false
  private var level = 0

  public init() {}

  public mutating func begin() {
    isActive = true
    level = 1
  }

  public mutating func end() {
    isActive = false
    level = 0
  }

  public mutating func handle(
    control: GamepadControl,
    isPressed: Bool
  ) -> ModelMenuNavigationAction? {
    guard isActive, isPressed else { return nil }
    switch control {
    case .dpadUp:
      return .up
    case .dpadDown:
      return .down
    case .dpadRight:
      if level == 1 { level = 2 }
      return .enter
    case .dpadLeft:
      if level > 1 {
        level -= 1
        return .back
      }
      end()
      return .cancel
    case .a:
      if level == 1 {
        level = 2
        return .enter
      }
      return .confirm
    case .b:
      if level > 1 {
        level -= 1
        return .back
      }
      end()
      return .cancel
    default:
      return nil
    }
  }
}

public enum PermissionMenuInputDecision: Equatable, Sendable {
  case navigate(ModelMenuNavigationAction)
  case consume
  case passthrough

  public var blocksBaseDispatch: Bool {
    switch self {
    case .navigate, .consume:
      return true
    case .passthrough:
      return false
    }
  }
}

/// Owns the controller inputs that are meaningful while Codex's one-level
/// permission picker is visible. Consuming both presses and releases prevents
/// the underlying base mappings from leaking through to the sidebar or panel.
public struct PermissionMenuNavigationState: Sendable {
  public private(set) var isActive = false

  public init() {}

  public mutating func begin() {
    isActive = true
  }

  public mutating func end() {
    isActive = false
  }

  public mutating func refresh(menuIsVisible: Bool) {
    if isActive && !menuIsVisible {
      end()
    }
  }

  public mutating func complete(
    _ navigation: ModelMenuNavigationAction,
    accepted: Bool
  ) {
    guard accepted else { return }
    if navigation == .confirm || navigation == .cancel {
      end()
    }
  }

  public mutating func handle(
    control: GamepadControl,
    isPressed: Bool
  ) -> PermissionMenuInputDecision {
    guard isActive else { return .passthrough }

    let ownedControls: Set<GamepadControl> = [
      .a, .b, .x, .y,
      .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
    ]
    guard ownedControls.contains(control) else { return .passthrough }
    guard isPressed else { return .consume }

    switch control {
    case .dpadUp:
      return .navigate(.up)
    case .dpadDown:
      return .navigate(.down)
    case .a:
      return .navigate(.confirm)
    case .b, .dpadLeft:
      return .navigate(.cancel)
    default:
      return .consume
    }
  }
}

public enum StickDirection: String, Codable, Equatable, Sendable {
  case up, right, down, left
}

public struct StickGate: Sendable {
  public let activationThreshold: Float
  public let releaseThreshold: Float
  private var isLatched = false

  public init(activationThreshold: Float = 0.72, releaseThreshold: Float = 0.3) {
    precondition(releaseThreshold < activationThreshold)
    self.activationThreshold = activationThreshold
    self.releaseThreshold = releaseThreshold
  }

  public mutating func update(x: Float, y: Float) -> StickDirection? {
    let magnitude = max(abs(x), abs(y))
    if isLatched {
      if magnitude <= releaseThreshold {
        isLatched = false
      }
      return nil
    }
    guard magnitude >= activationThreshold else {
      return nil
    }

    isLatched = true
    if abs(x) > abs(y) {
      return x >= 0 ? .right : .left
    }
    return y >= 0 ? .up : .down
  }
}

public struct StickRepeatGate: Sendable {
  public let activationThreshold: Float
  public let releaseThreshold: Float
  public let initialDelay: TimeInterval
  public let repeatInterval: TimeInterval
  private var direction: StickDirection?
  private var nextRepeatAt: TimeInterval?

  public init(
    activationThreshold: Float = 0.72,
    releaseThreshold: Float = 0.30,
    initialDelay: TimeInterval = 0.30,
    repeatInterval: TimeInterval = 0.07
  ) {
    self.activationThreshold = activationThreshold
    self.releaseThreshold = releaseThreshold
    self.initialDelay = initialDelay
    self.repeatInterval = repeatInterval
  }

  public mutating func update(x: Float, y: Float, at time: TimeInterval) -> StickDirection? {
    let magnitude = max(abs(x), abs(y))
    guard magnitude >= releaseThreshold else {
      direction = nil
      nextRepeatAt = nil
      return nil
    }
    guard magnitude >= activationThreshold else { return nil }

    let candidate: StickDirection
    if abs(x) > abs(y) {
      candidate = x >= 0 ? .right : .left
    } else {
      candidate = y >= 0 ? .up : .down
    }

    guard direction == candidate else {
      direction = candidate
      nextRepeatAt = time + initialDelay
      return candidate
    }
    guard let nextRepeatAt, time >= nextRepeatAt else { return nil }
    self.nextRepeatAt = time + repeatInterval
    return candidate
  }
}

public enum TriggerTransition: Equatable, Sendable {
  case pressed
  case released
}

public struct TriggerPressGate: Sendable {
  public let pressThreshold: Float
  public let releaseThreshold: Float
  private var isPressed = false

  public init(pressThreshold: Float = 0.55, releaseThreshold: Float = 0.3) {
    precondition(releaseThreshold < pressThreshold)
    self.pressThreshold = pressThreshold
    self.releaseThreshold = releaseThreshold
  }

  public mutating func update(value: Float) -> TriggerTransition? {
    if isPressed {
      guard value <= releaseThreshold else { return nil }
      isPressed = false
      return .released
    }
    guard value >= pressThreshold else { return nil }
    isPressed = true
    return .pressed
  }
}

public enum ButtonTransition: Equatable, Sendable {
  case press
  case release
}

public enum SubmitOrNewlineAction: Equatable, Sendable {
  case submit
  case newline
}

public struct SubmitOrNewlineMachine: Sendable {
  public let holdDuration: TimeInterval
  private var startedAt: TimeInterval?
  private var insertedNewline = false

  public var isActive: Bool { startedAt != nil }

  public init(holdDuration: TimeInterval = 0.40) {
    self.holdDuration = holdDuration
  }

  public mutating func handle(_ event: ButtonTransition, at time: TimeInterval) -> [SubmitOrNewlineAction] {
    switch event {
    case .press:
      guard startedAt == nil else { return [] }
      startedAt = time
      insertedNewline = false
      return []
    case .release:
      guard startedAt != nil else { return [] }
      let action: [SubmitOrNewlineAction] = insertedNewline ? [] : [.submit]
      startedAt = nil
      insertedNewline = false
      return action
    }
  }

  public mutating func advance(to time: TimeInterval) -> [SubmitOrNewlineAction] {
    guard !insertedNewline, let startedAt, time >= startedAt + holdDuration else { return [] }
    insertedNewline = true
    return [.newline]
  }
}

public enum PushToTalkAction: Equatable, Sendable {
  case start
  case stop
}

public enum PushToTalkState: Equatable, Sendable {
  case idle
  case pressed(at: TimeInterval)
  case waitingForSecondPress(until: TimeInterval)
  case latched
  case suppressingPresses(until: TimeInterval)
}

public struct PushToTalkMachine: Sendable {
  public let doubleTapWindow: TimeInterval
  public private(set) var state: PushToTalkState = .idle

  public init(doubleTapWindow: TimeInterval = 0.35) {
    self.doubleTapWindow = doubleTapWindow
  }

  public mutating func handle(
    _ transition: ButtonTransition,
    at time: TimeInterval
  ) -> [PushToTalkAction] {
    var actions = advance(to: time)

    switch state {
    case .idle:
      if transition == .press {
        state = .pressed(at: time)
        actions.append(.start)
      }
    case .pressed(let pressedAt):
      if transition == .release {
        let deadline = pressedAt + doubleTapWindow
        if time >= deadline {
          state = .idle
          actions.append(.stop)
        } else {
          state = .waitingForSecondPress(until: deadline)
        }
      }
    case .waitingForSecondPress(let deadline):
      if transition == .press, time < deadline {
        state = .latched
      }
    case .latched:
      if transition == .press {
        state = .suppressingPresses(until: time + doubleTapWindow)
        actions.append(.stop)
      }
    case .suppressingPresses:
      break
    }

    return actions
  }

  public mutating func advance(to time: TimeInterval) -> [PushToTalkAction] {
    switch state {
    case .waitingForSecondPress(let deadline) where time >= deadline:
      state = .idle
      return [.stop]
    case .suppressingPresses(let deadline) where time >= deadline:
      state = .idle
      return []
    default:
      return []
    }
  }
}

public struct LongPressGate: Sendable {
  public let duration: TimeInterval
  private var startedAt: TimeInterval?
  private var hasFired = false

  public init(duration: TimeInterval) {
    self.duration = duration
  }

  public mutating func begin(at time: TimeInterval) {
    startedAt = time
    hasFired = false
  }

  public mutating func cancel() {
    startedAt = nil
    hasFired = false
  }

  public mutating func update(at time: TimeInterval) -> Bool {
    guard !hasFired, let startedAt, time >= startedAt + duration else {
      return false
    }
    hasFired = true
    return true
  }
}

public enum TapOrHoldResult: Equatable, Sendable {
  case tap
  case hold
  case cancelled
}

public struct TapOrHoldGate: Sendable {
  public let duration: TimeInterval
  private var startedAt: TimeInterval?
  private var didHold = false

  public init(duration: TimeInterval) {
    self.duration = duration
  }

  public mutating func begin(at time: TimeInterval) {
    startedAt = time
    didHold = false
  }

  public mutating func update(at time: TimeInterval) -> Bool {
    guard !didHold, let startedAt, time >= startedAt + duration else {
      return false
    }
    didHold = true
    return true
  }

  public mutating func end(at time: TimeInterval) -> TapOrHoldResult {
    guard startedAt != nil else { return .cancelled }
    _ = update(at: time)
    let result: TapOrHoldResult = didHold ? .hold : .tap
    startedAt = nil
    didHold = false
    return result
  }

  public mutating func cancel() {
    startedAt = nil
    didHold = false
  }
}

public struct MappingConfiguration: Codable, Equatable, Sendable {
  public var layers: [String: [String: String]]

  public init(layers: [String: [String: String]]) {
    self.layers = layers
  }

  public func action(for control: GamepadControl, layer: BridgeLayer) -> String? {
    layers[layer.rawValue]?[control.rawValue]
  }

  public mutating func setAction(
    _ actionID: String?,
    for control: GamepadControl,
    layer: BridgeLayer
  ) {
    var mapping = layers[layer.rawValue] ?? [:]
    mapping[control.rawValue] = actionID
    layers[layer.rawValue] = mapping
  }

  public static let `default` = MappingConfiguration(layers: [
    BridgeLayer.base.rawValue: [
      GamepadControl.lt.rawValue: "pushToTalk",
      GamepadControl.rt.rawValue: "submit",
      GamepadControl.a.rawValue: "toggleSidePanel",
      GamepadControl.b.rawValue: "cancel",
      GamepadControl.x.rawValue: "toggleBottomPanel",
      GamepadControl.y.rawValue: "newTask",
      GamepadControl.dpadUp.rawValue: "toggleSidebar",
      GamepadControl.dpadDown.rawValue: "toggleBottomPanel",
      GamepadControl.dpadLeft.rawValue: "previousTask",
      GamepadControl.dpadRight.rawValue: "nextTask",
      GamepadControl.leftStickLeft.rawValue: "composerMoveLeft",
      GamepadControl.leftStickRight.rawValue: "composerMoveRight",
      GamepadControl.leftStickUp.rawValue: "composerMoveLineStart",
      GamepadControl.leftStickDown.rawValue: "composerMoveLineEnd",
      GamepadControl.rightStickLeft.rawValue: "composerSelectLeft",
      GamepadControl.rightStickRight.rawValue: "composerSelectRight",
      GamepadControl.rightStickUp.rawValue: "composerSelectLineStart",
      GamepadControl.rightStickDown.rawValue: "composerSelectLineEnd",
      GamepadControl.l3.rawValue: "composerDeleteBackward",
      GamepadControl.r3.rawValue: "focusComposer",
      GamepadControl.menu.rawValue: "toggleSidebar",
      GamepadControl.view.rawValue: "windowSwitcher",
      GamepadControl.home.rawValue: "launchCodex",
      GamepadControl.share.rawValue: "launchCodex",
    ],
    BridgeLayer.task.rawValue: [
      GamepadControl.a.rawValue: "selectionAddToTask",
      GamepadControl.b.rawValue: "cancel",
      GamepadControl.x.rawValue: "selectionAskSideChat",
      GamepadControl.y.rawValue: "selectionMoreDetails",
      GamepadControl.dpadLeft.rawValue: "previousTask",
      GamepadControl.dpadRight.rawValue: "nextTask",
      GamepadControl.dpadUp.rawValue: "togglePin",
      GamepadControl.rt.rawValue: "newTask",
    ],
    BridgeLayer.developer.rawValue: [
      GamepadControl.a.rawValue: "modelPicker",
      GamepadControl.b.rawValue: "terminal",
      GamepadControl.x.rawValue: "fastToggle",
      GamepadControl.y.rawValue: "planToggle",
      GamepadControl.rt.rawValue: "submitWithNotification",
      GamepadControl.dpadDown.rawValue: "toggleBottomPanel",
      GamepadControl.l3.rawValue: "openFolder",
    ],
    BridgeLayer.safety.rawValue: [
      GamepadControl.a.rawValue: "approve",
      GamepadControl.b.rawValue: "decline",
      GamepadControl.y.rawValue: "permissionPicker",
      GamepadControl.dpadUp.rawValue: "togglePin",
    ],
    BridgeLayer.system.rawValue: [
      GamepadControl.a.rawValue: "settings",
      GamepadControl.b.rawValue: "keyboardShortcuts",
      GamepadControl.x.rawValue: "newProjectlessTask",
      GamepadControl.y.rawValue: "newProject",
      GamepadControl.dpadLeft.rawValue: "previousWindow",
      GamepadControl.dpadRight.rawValue: "nextWindow",
      GamepadControl.menu.rawValue: "feedback",
    ],
  ])
}

public enum MappingConfigurationMigration {
  public static func addingPermissionPickerIfMissing(
    to configuration: MappingConfiguration
  ) -> MappingConfiguration {
    guard configuration.action(for: .y, layer: .safety) == nil else {
      return configuration
    }
    var migrated = configuration
    migrated.setAction("permissionPicker", for: .y, layer: .safety)
    return migrated
  }

  public static func addingCompletionNotificationIfMissing(
    to configuration: MappingConfiguration
  ) -> MappingConfiguration {
    guard configuration.action(for: .rt, layer: .developer) == nil else {
      return configuration
    }
    var migrated = configuration
    migrated.setAction("submitWithNotification", for: .rt, layer: .developer)
    return migrated
  }
}

public enum MappingValidationError: LocalizedError, Equatable {
  case unknownLayer(String)
  case unknownControl(String)
  case unknownAction(String)
  case tooManyMappings

  public var errorDescription: String? {
    switch self {
    case .unknownLayer(let layer):
      return "Unknown layer: \(layer)"
    case .unknownControl(let control):
      return "Unknown control: \(control)"
    case .unknownAction(let action):
      return "Unknown action: \(action)"
    case .tooManyMappings:
      return "Mapping contains too many entries"
    }
  }
}

public enum MappingValidator {
  public static func validate(_ configuration: MappingConfiguration) throws {
    let layers = Set(BridgeLayer.allCases.map(\.rawValue))
    let controls = Set(GamepadControl.allCases.map(\.rawValue))
    let actions = Set(ActionCatalog.all.map(\.id))
    var count = 0

    for (layer, mappings) in configuration.layers {
      guard layers.contains(layer) else {
        throw MappingValidationError.unknownLayer(layer)
      }
      for (control, action) in mappings {
        count += 1
        guard count <= 256 else {
          throw MappingValidationError.tooManyMappings
        }
        guard controls.contains(control) else {
          throw MappingValidationError.unknownControl(control)
        }
        guard actions.contains(action) else {
          throw MappingValidationError.unknownAction(action)
        }
      }
    }
  }
}
