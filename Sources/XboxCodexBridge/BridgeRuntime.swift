import AppKit
import ApplicationServices
import Foundation
import XboxCodexBridgeCore

struct AxisSnapshot: Codable {
  var leftX: Float = 0
  var leftY: Float = 0
  var rightX: Float = 0
  var rightY: Float = 0
}

struct CapabilitySnapshot: Codable {
  var haptics = false
  var light = false
  var shareButton = false
  var accessibility = false
}

struct BridgeSnapshot: Codable {
  var connected = false
  var controllerName: String?
  var pressed: [String] = []
  var axes = AxisSnapshot()
  var activeLayer = BridgeLayer.base.rawValue
  var lastAction: String?
  var lastActionResult: String?
  var lastMessage = "Waiting for an Xbox controller"
  var completionSequence = 0
  var pushToTalkState = "idle"
  var capabilities = CapabilitySnapshot()

  mutating func recordCompletion() {
    completionSequence &+= 1
  }

  mutating func recordActionStart(id: String, message: String) {
    lastAction = id
    lastActionResult = nil
    lastMessage = message
  }

  mutating func recordActionResult(_ message: String) {
    lastActionResult = message
    lastMessage = message
  }
}

enum RuntimeError: LocalizedError {
  case unknownAction
  case unsafeTestAction
  case windowNotFound

  var errorDescription: String? {
    switch self {
    case .unknownAction:
      return "Unknown action"
    case .unsafeTestAction:
      return "This action can only run from the physical controller"
    case .windowNotFound:
      return "Codex window is no longer available"
    }
  }
}

enum R3GestureActionRouter {
  static func actionID(for result: TapOrHoldResult) -> String? {
    switch result {
    case .tap: return nil
    case .hold: return "clearComposer"
    case .cancelled: return nil
    }
  }
}

struct ActionSuccessFeedback {
  private let playHaptic: () -> Void

  init(_ playHaptic: @escaping () -> Void) {
    self.playHaptic = playHaptic
  }

  func handle(actionID: String, result: DispatchResult) {
    // Successful controller actions use the HUD only. Automatic haptics are
    // reserved for verified approvals and explicitly tracked completion tasks;
    // manual tests use /api/haptic.
  }
}

final class BridgeRuntime {
  private let dispatcher: CommandDispatcher
  private let dictationController: CodexDictationController
  private let controllerService: ControllerService
  private let actionSuccessFeedback: ActionSuccessFeedback
  private let approvalHapticCoordinator: ApprovalHapticCoordinator
  private var turnCompletionHapticCoordinator: TurnCompletionHapticCoordinator?
  private let windowSwitcherController: WindowSwitcherController
  private let projectPickerController: ProjectPickerController
  private let configURL: URL
  private let lock = NSLock()
  private var configuration: MappingConfiguration
  private var snapshot = BridgeSnapshot()

  private var pressed = Set<GamepadControl>()
  private var leftStickGate = StickRepeatGate()
  private var rightStickGate = StickRepeatGate()
  private var stickRepeatItems: [Bool: DispatchWorkItem] = [:]
  private var pushToTalk = PushToTalkMachine()
  private var pushToTalkDeadline: DispatchWorkItem?
  private var submitOrNewline = SubmitOrNewlineMachine()
  private var submitOrNewlineDeadline: DispatchWorkItem?
  private var holdItems: [GamepadControl: DispatchWorkItem] = [:]
  private var viewUsedAsModifier = false
  private var viewActsAsModifier = false
  private var r3Gate = TapOrHoldGate(duration: 0.5)
  private var r3HoldItem: DispatchWorkItem?
  private var r3BaseGestureActive = false
  private var modelMenuNavigation = ModelMenuNavigationState()
  private var permissionMenuNavigation = PermissionMenuNavigationState()
  private var modifierChord = ModifierChordState()
  private var safetyYChord = SafetyYChordState()
  private var pendingBaseAItem: DispatchWorkItem?
  private var pendingSafetyYItem: DispatchWorkItem?
  private var pendingModelMenuAItem: DispatchWorkItem?

  init(
    dispatcher: CommandDispatcher,
    dictationController: CodexDictationController,
    controllerService: ControllerService,
    configURL: URL,
    actionSuccessFeedback: ActionSuccessFeedback? = nil,
    approvalHapticCoordinator: ApprovalHapticCoordinator? = nil,
    turnCompletionHapticCoordinator: TurnCompletionHapticCoordinator? = nil,
    windowSwitcherController: WindowSwitcherController = WindowSwitcherController(),
    projectPickerController: ProjectPickerController = ProjectPickerController()
  ) {
    self.dispatcher = dispatcher
    self.dictationController = dictationController
    self.controllerService = controllerService
    self.windowSwitcherController = windowSwitcherController
    self.projectPickerController = projectPickerController
    self.actionSuccessFeedback =
      actionSuccessFeedback
      ?? ActionSuccessFeedback {
        _ = controllerService.testHaptic()
      }
    self.approvalHapticCoordinator =
      approvalHapticCoordinator
      ?? ApprovalHapticCoordinator(detector: SystemCodexUIActionClient()) { kind in
        _ = controllerService.playHaptic(kind)
      }
    self.turnCompletionHapticCoordinator = turnCompletionHapticCoordinator
    self.configURL = configURL
    self.configuration = Self.loadConfiguration(from: configURL)
    snapshot.capabilities.accessibility = dispatcher.isAccessibilityTrusted
    if self.turnCompletionHapticCoordinator == nil {
      self.turnCompletionHapticCoordinator = TurnCompletionHapticCoordinator(
        detector: SystemCodexUIActionClient()
      ) { [weak self] _ in
        self?.signalTurnCompletion()
      }
    }
  }

  func start() {
    controllerService.onControl = { [weak self] control, isPressed in
      self?.handle(control: control, isPressed: isPressed)
    }
    controllerService.onStick = { [weak self] isLeft, x, y in
      self?.handleStick(isLeft: isLeft, x: x, y: y)
    }
    controllerService.onCapabilities = { [weak self] capabilities in
      self?.updateCapabilities(capabilities)
    }
    controllerService.start()
  }

  func currentSnapshot() -> BridgeSnapshot {
    lock.withLock {
      var value = snapshot
      value.capabilities.accessibility = dispatcher.isAccessibilityTrusted
      return value
    }
  }

  func currentConfiguration() -> MappingConfiguration {
    lock.withLock { configuration }
  }

  func updateConfiguration(_ newValue: MappingConfiguration) throws {
    try MappingValidator.validate(newValue)
    let data = try JSONEncoder.pretty.encode(newValue)
    let directory = configURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try data.write(to: configURL, options: .atomic)
    lock.withLock {
      configuration = newValue
      snapshot.lastMessage = "Mapping saved"
    }
  }

  func testAction(_ id: String) throws {
    guard let action = ActionCatalog.definition(for: id) else {
      throw RuntimeError.unknownAction
    }
    guard action.isSafeForWebTest else {
      throw RuntimeError.unsafeTestAction
    }
    dispatch(action)
  }

  func testHaptic() -> Bool {
    controllerService.testHaptic()
  }

  func testLight(red: Float, green: Float, blue: Float) -> Bool {
    controllerService.testLight(red: red, green: green, blue: blue)
  }

  func handleHookHaptic(_ event: HookHapticEvent) {
    switch event {
    case .turnStopped:
      turnCompletionHapticCoordinator?.handleTrackedTurnEnded()
    case .permissionRequest:
      approvalHapticCoordinator.handlePermissionRequest()
      setMessage("Checking for a human approval request…")
    }
  }

  private func signalTurnCompletion() {
    _ = controllerService.playHaptic(.turnStopped)
    lock.withLock {
      snapshot.recordCompletion()
      snapshot.lastMessage = "Codex turn ended — ready to review"
    }
  }

  func codexWindows() -> [CodexWindowInfo] {
    dispatcher.codexWindows()
  }

  func dictationDiagnostics() -> CodexDictationDiagnostics {
    dictationController.diagnostics()
  }

  func modelPickerCandidates() -> [CodexModelPickerCandidateMetadata] {
    dispatcher.modelPickerCandidates()
  }

  func visibleModelMenuItems() -> [CodexVisibleMenuItemMetadata] {
    dispatcher.visibleModelMenuItems()
  }

  func visibleModelOverlayElements() -> [CodexModelOverlayElementMetadata] {
    dispatcher.visibleModelOverlayElements()
  }

  func focusCodexWindow(id: String) throws {
    let title = codexWindows().first(where: { $0.id == id })?.title
    guard dispatcher.focusCodexWindow(id: id) else {
      throw RuntimeError.windowNotFound
    }
    setMessage("Focused \(title ?? "Codex window")")
  }

  private func handle(control: GamepadControl, isPressed: Bool) {
    let time = ProcessInfo.processInfo.systemUptime
    if isPressed {
      pressed.insert(control)
      if control != .view, pressed.contains(.view) {
        viewUsedAsModifier = true
      }
    } else {
      pressed.remove(control)
    }
    publishInputState()

    if windowSwitcherController.isPresented,
      windowSwitcherController.handle(control: control, isPressed: isPressed)
    {
      return
    }

    if permissionMenuNavigation.isActive {
      permissionMenuNavigation.refresh(
        menuIsVisible: dispatcher.isPermissionMenuVisible()
      )
    }

    if permissionMenuNavigation.isActive {
      let decision = permissionMenuNavigation.handle(control: control, isPressed: isPressed)
      if case .navigate(let navigation) = decision {
        dispatchPermissionMenuNavigation(navigation)
      }
      if decision.blocksBaseDispatch {
        return
      }
    }

    switch ModelPickerChordPlan.decision(
      control: control,
      isPressed: isPressed,
      pressed: pressed,
      modelMenuIsActive: modelMenuNavigation.isActive
    ) {
    case .reopen:
      pendingModelMenuAItem?.cancel()
      pendingModelMenuAItem = nil
      modelMenuNavigation.end()
      dispatchMapped(control: .a, layer: .developer)
      return
    case .deferMenuA:
      scheduleDeferredModelMenuA()
      return
    case .passthrough:
      break
    }

    if modelMenuNavigation.isActive {
      if isPressed, control != .a {
        pendingModelMenuAItem?.cancel()
        pendingModelMenuAItem = nil
      }
      if let navigation = modelMenuNavigation.handle(control: control, isPressed: isPressed) {
        dispatchModelMenuNavigation(navigation)
        return
      }
    }

    if let resolution = safetyYChord.handle(
      control: control,
      isPressed: isPressed,
      pressed: pressed
    ) {
      switch resolution {
      case .deferY:
        scheduleDeferredSafetyY()
      case .dispatchY(let layer):
        pendingSafetyYItem?.cancel()
        pendingSafetyYItem = nil
        dispatchMapped(control: .y, layer: layer)
      }
      return
    }

    if let resolution = modifierChord.handle(control: control, isPressed: isPressed, pressed: pressed) {
      switch resolution {
      case .deferBaseA:
        scheduleDeferredBaseA()
      case .dispatchA(let layer):
        pendingBaseAItem?.cancel()
        pendingBaseAItem = nil
        dispatchMapped(control: .a, layer: layer)
      }
      return
    }

    if control == .lt {
      handlePushToTalk(isPressed: isPressed, at: time)
      return
    }

    if control == .rt,
      submitOrNewline.isActive || LayerResolver.resolve(pressed: pressed) == .base
    {
      handleSubmitOrNewline(isPressed: isPressed, at: time)
      return
    }

    if control == .view {
      if isPressed {
        if pressed.contains(.lb) || pressed.contains(.rb) {
          viewActsAsModifier = false
          dispatchMapped(control: .view, layer: LayerResolver.resolve(pressed: pressed))
        } else {
          viewActsAsModifier = true
          viewUsedAsModifier = false
        }
      } else if viewActsAsModifier, !viewUsedAsModifier {
        dispatchMapped(control: .view, layer: .base)
      }
      if !isPressed { viewActsAsModifier = false }
      return
    }

    if control == .lb || control == .rb {
      return
    }

    let layer = LayerResolver.resolve(pressed: pressed)
    if control == .r3, layer == .base || r3BaseGestureActive {
      handleR3(isPressed: isPressed, at: time)
      return
    }
    guard let actionID = currentConfiguration().action(for: control, layer: layer),
      let action = ActionCatalog.definition(for: actionID)
    else {
      if isPressed {
        setMessage("No action assigned to \(control.rawValue) on \(layer.rawValue)")
      }
      return
    }

    if let duration = action.holdDuration {
      if isPressed {
        scheduleHold(action, control: control, layer: layer, duration: duration)
      } else {
        holdItems.removeValue(forKey: control)?.cancel()
      }
    } else if isPressed {
      dispatch(action)
    }
  }

  private func handleR3(isPressed: Bool, at time: TimeInterval) {
    if isPressed {
      r3BaseGestureActive = true
      r3Gate.begin(at: time)
      r3HoldItem?.cancel()
      let item = DispatchWorkItem { [weak self] in
        guard let self, self.r3BaseGestureActive,
          self.r3Gate.update(at: ProcessInfo.processInfo.systemUptime)
        else { return }
        self.dispatchR3Action(for: .hold)
      }
      r3HoldItem = item
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
      return
    }

    guard r3BaseGestureActive else { return }
    r3HoldItem?.cancel()
    r3HoldItem = nil
    let result = r3Gate.end(at: time)
    r3BaseGestureActive = false
    if result == .tap {
      dispatchMapped(control: .r3, layer: .base)
    }
  }

  private func dispatchR3Action(for result: TapOrHoldResult) {
    guard let actionID = R3GestureActionRouter.actionID(for: result),
      let action = ActionCatalog.definition(for: actionID)
    else { return }
    dispatch(action)
  }

  private func handleStick(isLeft: Bool, x: Float, y: Float) {
    let time = ProcessInfo.processInfo.systemUptime
    let direction: StickDirection?
    if isLeft {
      direction = leftStickGate.update(x: x, y: y, at: time)
    } else {
      direction = rightStickGate.update(x: x, y: y, at: time)
    }

    lock.withLock {
      if isLeft {
        snapshot.axes.leftX = x
        snapshot.axes.leftY = y
      } else {
        snapshot.axes.rightX = x
        snapshot.axes.rightY = y
      }
    }
    if permissionMenuNavigation.isActive, direction != nil {
      permissionMenuNavigation.refresh(
        menuIsVisible: dispatcher.isPermissionMenuVisible()
      )
    }
    guard !permissionMenuNavigation.isActive else {
      stickRepeatItems[isLeft]?.cancel()
      stickRepeatItems[isLeft] = nil
      return
    }
    scheduleStickRepeat(isLeft: isLeft, x: x, y: y)
    guard let direction else { return }

    let control: GamepadControl
    switch (isLeft, direction) {
    case (true, .up): control = .leftStickUp
    case (true, .right): control = .leftStickRight
    case (true, .down): control = .leftStickDown
    case (true, .left): control = .leftStickLeft
    case (false, .up): control = .rightStickUp
    case (false, .right): control = .rightStickRight
    case (false, .down): control = .rightStickDown
    case (false, .left): control = .rightStickLeft
    }
    dispatchMapped(control: control, layer: LayerResolver.resolve(pressed: pressed))
  }

  private func scheduleStickRepeat(isLeft: Bool, x: Float, y: Float) {
    stickRepeatItems[isLeft]?.cancel()
    guard max(abs(x), abs(y)) >= 0.72 else {
      stickRepeatItems[isLeft] = nil
      return
    }
    let item = DispatchWorkItem { [weak self] in
      self?.handleStick(isLeft: isLeft, x: x, y: y)
    }
    stickRepeatItems[isLeft] = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: item)
  }

  private func handlePushToTalk(isPressed: Bool, at time: TimeInterval) {
    pushToTalkDeadline?.cancel()
    let actions = pushToTalk.handle(isPressed ? .press : .release, at: time)
    applyPushToTalk(actions)
    publishPushToTalkState()

    if !isPressed {
      let workItem = DispatchWorkItem { [weak self] in
        guard let self else { return }
        let actions = self.pushToTalk.advance(
          to: ProcessInfo.processInfo.systemUptime
        )
        self.applyPushToTalk(actions)
        self.publishPushToTalkState()
      }
      pushToTalkDeadline = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: workItem)
    }
  }

  private func handleSubmitOrNewline(isPressed: Bool, at time: TimeInterval) {
    submitOrNewlineDeadline?.cancel()
    applySubmitOrNewline(submitOrNewline.handle(isPressed ? .press : .release, at: time))
    guard isPressed else { return }

    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.applySubmitOrNewline(self.submitOrNewline.advance(to: ProcessInfo.processInfo.systemUptime))
    }
    submitOrNewlineDeadline = item
    DispatchQueue.main.asyncAfter(deadline: .now() + submitOrNewline.holdDuration, execute: item)
  }

  private func applySubmitOrNewline(_ actions: [SubmitOrNewlineAction]) {
    for action in actions {
      let actionID = action == .submit ? "submit" : "insertNewline"
      guard let definition = ActionCatalog.definition(for: actionID) else { continue }
      dispatch(definition)
    }
  }

  private func applyPushToTalk(_ actions: [PushToTalkAction]) {
    guard let definition = ActionCatalog.definition(for: "pushToTalk") else { return }
    for action in actions {
      lock.withLock {
        snapshot.recordActionStart(
          id: definition.id,
          message: action == .start ? "Starting dictation…" : "Stopping dictation…"
        )
      }
      let phase: CodexDictationPhase = action == .start ? .start : .stop
      dictationController.perform(phase) { [weak self] result in
        self?.lock.withLock {
          self?.snapshot.recordActionResult(result.message)
        }
      }
    }
  }

  private func publishPushToTalkState() {
    let label: String
    switch pushToTalk.state {
    case .idle: label = "idle"
    case .pressed: label = "recording"
    case .waitingForSecondPress: label = "recording"
    case .latched: label = "latched"
    case .suppressingPresses: label = "stopping"
    }
    lock.withLock { snapshot.pushToTalkState = label }
  }

  private func scheduleHold(
    _ action: ActionDefinition,
    control: GamepadControl,
    layer: BridgeLayer,
    duration: TimeInterval
  ) {
    holdItems.removeValue(forKey: control)?.cancel()
    setMessage("Hold \(action.label) for \(String(format: "%.2g", duration))s")
    let item = DispatchWorkItem { [weak self] in
      guard let self,
        self.pressed.contains(control),
        LayerResolver.resolve(pressed: self.pressed) == layer
      else { return }
      self.dispatch(action)
      self.holdItems.removeValue(forKey: control)
    }
    holdItems[control] = item
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
  }

  private func dispatchMapped(control: GamepadControl, layer: BridgeLayer) {
    guard let actionID = currentConfiguration().action(for: control, layer: layer),
      let action = ActionCatalog.definition(for: actionID)
    else {
      setMessage("No action assigned to \(control.rawValue) on \(layer.rawValue)")
      return
    }
    dispatch(action)
  }

  private func scheduleDeferredBaseA() {
    pendingBaseAItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self,
        let resolution = self.modifierChord.consumeDeferredBaseA()
      else { return }
      self.pendingBaseAItem = nil
      if case .dispatchA(let layer) = resolution {
        self.dispatchMapped(control: .a, layer: layer)
      }
    }
    pendingBaseAItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
  }

  private func scheduleDeferredSafetyY() {
    pendingSafetyYItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self,
        let resolution = self.safetyYChord.consumeDeferredY()
      else { return }
      self.pendingSafetyYItem = nil
      if case .dispatchY(let layer) = resolution {
        self.dispatchMapped(control: .y, layer: layer)
      }
    }
    pendingSafetyYItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
  }

  private func scheduleDeferredModelMenuA() {
    pendingModelMenuAItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pendingModelMenuAItem = nil
      guard
        let navigation = self.modelMenuNavigation.handle(control: .a, isPressed: true)
      else { return }
      self.dispatchModelMenuNavigation(navigation)
    }
    pendingModelMenuAItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
  }

  private func dispatch(_ action: ActionDefinition, message: String? = nil) {
    lock.withLock {
      snapshot.lastAction = action.id
      snapshot.lastActionResult = nil
      snapshot.lastMessage = message ?? "Sending \(action.label)…"
    }
    if action.id == "windowSwitcher" {
      showWindowSwitcher()
      return
    }
    dispatcher.perform(action) { [weak self] result in
      guard let self else { return }
      if CompletionNotificationArmingPolicy.shouldArm(actionID: action.id), result.accepted {
        self.turnCompletionHapticCoordinator?.handleSubmit()
      }
      if action.id == "modelPicker" {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.permissionMenuNavigation.end()
          self.modelMenuNavigation.end()
          guard
            let initialNavigation = ModelMenuActivationPlan.initialNavigation(
              openAccepted: result.accepted
            )
          else { return }
          self.modelMenuNavigation.begin()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.dispatchModelMenuNavigation(initialNavigation)
          }
        }
      }
      if action.id == "permissionPicker" {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.modelMenuNavigation.end()
          self.permissionMenuNavigation.end()
          guard result.accepted else { return }
          self.permissionMenuNavigation.begin()
        }
      }
      self.actionSuccessFeedback.handle(actionID: action.id, result: result)
      self.lock.withLock {
        self.snapshot.lastActionResult = result.message
        self.snapshot.lastMessage = result.message
      }
    }
  }

  private func dispatchModelMenuNavigation(_ navigation: ModelMenuNavigationAction) {
    let label: String
    switch navigation {
    case .up: label = "Previous model menu item"
    case .down: label = "Next model menu item"
    case .enter: label = "Enter model submenu"
    case .back: label = "Return to parent model menu"
    case .confirm: label = "Confirm model menu selection"
    case .cancel: label = "Cancel model menu selection"
    }
    lock.withLock {
      snapshot.lastAction = "modelMenu\(label.replacingOccurrences(of: " ", with: ""))"
      snapshot.lastActionResult = nil
      snapshot.lastMessage = "Sending \(label)…"
    }
    dispatcher.performModelMenuNavigation(navigation) { [weak self] result in
      guard let self else { return }
      self.lock.withLock {
        self.snapshot.lastActionResult = result.message
        self.snapshot.lastMessage = result.message
      }
    }
  }

  private func dispatchPermissionMenuNavigation(_ navigation: ModelMenuNavigationAction) {
    let label: String
    switch navigation {
    case .up: label = "Previous permission mode"
    case .down: label = "Next permission mode"
    case .confirm, .enter: label = "Confirm permission mode"
    case .cancel, .back: label = "Cancel permission mode selection"
    }
    lock.withLock {
      snapshot.lastAction = "permissionMenu\(label.replacingOccurrences(of: " ", with: ""))"
      snapshot.lastActionResult = nil
      snapshot.lastMessage = "Sending \(label)…"
    }
    dispatcher.performPermissionMenuNavigation(navigation) { [weak self] result in
      guard let self else { return }
      DispatchQueue.main.async { [weak self] in
        self?.permissionMenuNavigation.complete(navigation, accepted: result.accepted)
      }
      self.lock.withLock {
        self.snapshot.lastActionResult = result.message
        self.snapshot.lastMessage = result.message
      }
    }
  }

  private func showWindowSwitcher() {
    let entries = dispatcher.codexWindowMenuEntries()
    guard !entries.isEmpty else {
      setMessage("No Codex windows are available")
      return
    }
    setMessage("Choose one of \(entries.count) Codex windows")
    windowSwitcherController.present(entries: entries) { [weak self] entry in
      guard let self else { return }
      let focused = self.dispatcher.focusCodexWindowMenuEntry(id: entry.id)
      self.setMessage(focused ? "Focused \(entry.title)" : "Codex window is unavailable")
    }
  }

  private func showProjectPicker() {
    setMessage("Choose or create an independent project folder")
    projectPickerController.chooseFolder { [weak self] folder in
      guard let self else { return }
      guard let folder else {
        self.setMessage("Project selection cancelled")
        return
      }
      guard let deepLink = CodexProjectDeepLink.url(for: folder) else {
        self.setMessage("Selected project path is invalid")
        return
      }
      let opened = NSWorkspace.shared.open(deepLink)
      self.setMessage(
        opened
          ? "Opened independent project: \(folder.lastPathComponent)"
          : "Codex could not open the selected project"
      )
    }
  }

  private func updateCapabilities(_ capabilities: ControllerCapabilities) {
    lock.withLock {
      snapshot.connected = capabilities.connected
      snapshot.controllerName = capabilities.name
      snapshot.capabilities.haptics = capabilities.hasHaptics
      snapshot.capabilities.light = capabilities.hasLight
      snapshot.capabilities.shareButton = capabilities.hasShareButton
      snapshot.lastMessage =
        capabilities.connected
        ? "Controller connected"
        : "Waiting for an Xbox controller"
    }
  }

  private func publishInputState() {
    lock.withLock {
      snapshot.pressed = pressed.map(\.rawValue).sorted()
      snapshot.activeLayer = LayerResolver.resolve(pressed: pressed).rawValue
    }
  }

  private func setMessage(_ message: String) {
    lock.withLock { snapshot.lastMessage = message }
  }

  private static func loadConfiguration(from url: URL) -> MappingConfiguration {
    guard let data = try? Data(contentsOf: url),
      let value = try? JSONDecoder().decode(MappingConfiguration.self, from: data),
      (try? MappingValidator.validate(value)) != nil
    else {
      return .default
    }
    let permissionMigrated = MappingConfigurationMigration.addingPermissionPickerIfMissing(
      to: value
    )
    return MappingConfigurationMigration.addingCompletionNotificationIfMissing(
      to: permissionMigrated
    )
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

extension JSONEncoder {
  fileprivate static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
