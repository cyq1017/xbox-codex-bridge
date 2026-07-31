import XCTest

@testable import XboxCodexBridgeCore

final class BridgeCoreTests: XCTestCase {
  func testWindowSwitcherOverlayTakesPriorityOverChordAndMenuInput() {
    XCTAssertEqual(
      OverlayInputPriority.resolve(windowSwitcherIsPresented: true, modelMenuIsActive: true),
      .windowSwitcher
    )
    XCTAssertEqual(
      OverlayInputPriority.resolve(windowSwitcherIsPresented: false, modelMenuIsActive: true),
      .modelMenu
    )
  }

  func testModelPickerChordCanRecoverAStaleMenuInEitherBluetoothEventOrder() {
    XCTAssertEqual(
      ModelPickerChordPlan.decision(
        control: .a,
        isPressed: true,
        pressed: [.rb, .a],
        modelMenuIsActive: true
      ),
      .reopen
    )
    XCTAssertEqual(
      ModelPickerChordPlan.decision(
        control: .rb,
        isPressed: true,
        pressed: [.a, .rb],
        modelMenuIsActive: true
      ),
      .reopen
    )
    XCTAssertEqual(
      ModelPickerChordPlan.decision(
        control: .a,
        isPressed: true,
        pressed: [.a],
        modelMenuIsActive: true
      ),
      .deferMenuA
    )
    XCTAssertEqual(
      ModelPickerChordPlan.decision(
        control: .a,
        isPressed: false,
        pressed: [.rb],
        modelMenuIsActive: true
      ),
      .passthrough
    )
    XCTAssertEqual(
      ModelPickerChordPlan.decision(
        control: .a,
        isPressed: true,
        pressed: [.lb, .rb, .a],
        modelMenuIsActive: true
      ),
      .deferMenuA
    )
  }

  func testStickRepeatGateRepeatsWhileTheStickIsHeldInOneDirection() {
    var gate = StickRepeatGate(initialDelay: 0.30, repeatInterval: 0.10)

    XCTAssertEqual(gate.update(x: 0.9, y: 0, at: 0), .right)
    XCTAssertNil(gate.update(x: 0.9, y: 0, at: 0.29))
    XCTAssertEqual(gate.update(x: 0.9, y: 0, at: 0.30), .right)
    XCTAssertEqual(gate.update(x: 0.9, y: 0, at: 0.40), .right)
    XCTAssertNil(gate.update(x: 0, y: 0, at: 0.41))
    XCTAssertEqual(gate.update(x: 0, y: -0.9, at: 0.42), .down)
  }

  func testSubmitOrNewlineMachineSendsOnTapAndInsertsNewlineOnHold() {
    var machine = SubmitOrNewlineMachine(holdDuration: 0.40)

    XCTAssertEqual(machine.handle(.press, at: 0), [])
    XCTAssertEqual(machine.handle(.release, at: 0.15), [.submit])

    XCTAssertEqual(machine.handle(.press, at: 1.0), [])
    XCTAssertEqual(machine.advance(to: 1.39), [])
    XCTAssertEqual(machine.advance(to: 1.40), [.newline])
    XCTAssertEqual(machine.handle(.release, at: 1.50), [])
  }

  func testModifierChordLetsRBAClaimAnAEvenWhenAEventArrivesFirst() {
    var chord = ModifierChordState()

    XCTAssertEqual(chord.handle(control: .a, isPressed: true, pressed: [.a]), .deferBaseA)
    XCTAssertEqual(
      chord.handle(control: .rb, isPressed: true, pressed: [.a, .rb]),
      .dispatchA(.developer)
    )
    XCTAssertNil(chord.consumeDeferredBaseA())
  }

  func testModifierChordFlushesAnUnclaimedAAsTheBaseAction() {
    var chord = ModifierChordState()

    XCTAssertEqual(chord.handle(control: .a, isPressed: true, pressed: [.a]), .deferBaseA)
    XCTAssertEqual(chord.consumeDeferredBaseA(), .dispatchA(.base))
  }

  func testSafetyYChordSurvivesYArrivingBeforeTheSecondBumper() {
    var chord = SafetyYChordState()

    XCTAssertEqual(
      chord.handle(control: .y, isPressed: true, pressed: [.lb, .y]),
      .deferY
    )
    XCTAssertEqual(
      chord.handle(control: .rb, isPressed: true, pressed: [.lb, .rb, .y]),
      .dispatchY(.safety)
    )
    XCTAssertNil(chord.consumeDeferredY())
  }

  func testSafetyYChordFlushesAnUnclaimedYToItsOriginalLayer() {
    var chord = SafetyYChordState()

    XCTAssertEqual(
      chord.handle(control: .y, isPressed: true, pressed: [.rb, .y]),
      .deferY
    )
    XCTAssertEqual(chord.consumeDeferredY(), .dispatchY(.developer))
  }

  func testSafetyYChordDoesNotDelayYWhenBothBumpersAreAlreadyHeld() {
    var chord = SafetyYChordState()

    XCTAssertNil(
      chord.handle(control: .y, isPressed: true, pressed: [.lb, .rb, .y])
    )
    XCTAssertNil(chord.consumeDeferredY())
  }

  func testSafetyYChordClearsAnOlderPendingYWhenSafetyYArrivesDirectly() {
    var chord = SafetyYChordState()

    XCTAssertEqual(
      chord.handle(control: .y, isPressed: true, pressed: [.y]),
      .deferY
    )
    XCTAssertNil(
      chord.handle(control: .y, isPressed: true, pressed: [.lb, .rb, .y])
    )
    XCTAssertNil(chord.consumeDeferredY())
  }

  func testLayerResolverUsesSafetyBeforeOtherModifiers() {
    XCTAssertEqual(LayerResolver.resolve(pressed: [.lb, .rb, .view]), .safety)
    XCTAssertEqual(LayerResolver.resolve(pressed: [.lb]), .task)
    XCTAssertEqual(LayerResolver.resolve(pressed: [.rb]), .developer)
    XCTAssertEqual(LayerResolver.resolve(pressed: [.view]), .system)
    XCTAssertEqual(LayerResolver.resolve(pressed: []), .base)
  }

  func testModelMenuNavigationTracksTwoKeyboardMenuLevels() {
    var navigation = ModelMenuNavigationState()
    navigation.begin()

    XCTAssertTrue(navigation.isActive)
    XCTAssertEqual(navigation.handle(control: .dpadUp, isPressed: true), .up)
    XCTAssertEqual(navigation.handle(control: .dpadDown, isPressed: true), .down)
    XCTAssertEqual(navigation.handle(control: .a, isPressed: true), .enter)
    XCTAssertTrue(navigation.isActive)
    XCTAssertEqual(navigation.handle(control: .a, isPressed: true), .confirm)
    XCTAssertTrue(navigation.isActive)

    // Codex keeps its flyout submenu open after confirming a model or effort.
    XCTAssertEqual(navigation.handle(control: .a, isPressed: true), .confirm)
    XCTAssertEqual(navigation.handle(control: .b, isPressed: true), .back)
    XCTAssertTrue(navigation.isActive)

    XCTAssertEqual(navigation.handle(control: .dpadRight, isPressed: true), .enter)
    XCTAssertEqual(navigation.handle(control: .dpadLeft, isPressed: true), .back)
    XCTAssertTrue(navigation.isActive)

    XCTAssertEqual(navigation.handle(control: .b, isPressed: true), .cancel)
    XCTAssertFalse(navigation.isActive)
    XCTAssertNil(navigation.handle(control: .dpadDown, isPressed: false))
  }

  func testModelMenuLeftClosesOnlyFromTheFirstLevel() {
    var navigation = ModelMenuNavigationState()
    navigation.begin()

    XCTAssertEqual(navigation.handle(control: .dpadRight, isPressed: true), .enter)
    XCTAssertEqual(navigation.handle(control: .dpadLeft, isPressed: true), .back)
    XCTAssertTrue(navigation.isActive)
    XCTAssertEqual(navigation.handle(control: .dpadLeft, isPressed: true), .cancel)
    XCTAssertFalse(navigation.isActive)
  }

  func testPermissionMenuOwnsFaceButtonsAndDpadUntilSelectionFinishes() {
    var navigation = PermissionMenuNavigationState()
    navigation.begin()

    XCTAssertTrue(navigation.isActive)
    XCTAssertEqual(navigation.handle(control: .dpadUp, isPressed: true), .navigate(.up))
    XCTAssertEqual(navigation.handle(control: .dpadDown, isPressed: true), .navigate(.down))
    XCTAssertEqual(navigation.handle(control: .dpadRight, isPressed: true), .consume)
    XCTAssertEqual(navigation.handle(control: .x, isPressed: true), .consume)
    XCTAssertEqual(navigation.handle(control: .y, isPressed: true), .consume)
    XCTAssertEqual(navigation.handle(control: .a, isPressed: false), .consume)
    XCTAssertEqual(navigation.handle(control: .a, isPressed: true), .navigate(.confirm))
    XCTAssertTrue(navigation.isActive)
    navigation.complete(.confirm, accepted: true)
    XCTAssertFalse(navigation.isActive)
    XCTAssertEqual(navigation.handle(control: .dpadDown, isPressed: true), .passthrough)
  }

  func testPermissionMenuCancelsWithBOrLeft() {
    var navigation = PermissionMenuNavigationState()
    navigation.begin()

    XCTAssertEqual(navigation.handle(control: .b, isPressed: true), .navigate(.cancel))
    XCTAssertTrue(navigation.isActive)
    navigation.complete(.cancel, accepted: true)
    XCTAssertFalse(navigation.isActive)

    navigation.begin()
    XCTAssertEqual(navigation.handle(control: .dpadLeft, isPressed: true), .navigate(.cancel))
    XCTAssertTrue(navigation.isActive)
    navigation.complete(.cancel, accepted: true)
    XCTAssertFalse(navigation.isActive)
  }

  func testPermissionMenuFirstAConfirmsTheHighlightedMode() {
    var navigation = PermissionMenuNavigationState()
    navigation.begin()

    XCTAssertEqual(navigation.handle(control: .a, isPressed: true), .navigate(.confirm))
    XCTAssertTrue(navigation.isActive)
    navigation.complete(.confirm, accepted: true)
    XCTAssertFalse(navigation.isActive)
  }

  func testPermissionMenuKeepsControllerOwnershipWhenConfirmOrCancelFails() {
    var navigation = PermissionMenuNavigationState()
    navigation.begin()

    XCTAssertEqual(navigation.handle(control: .dpadDown, isPressed: true), .navigate(.down))
    XCTAssertEqual(navigation.handle(control: .a, isPressed: true), .navigate(.confirm))
    navigation.complete(.confirm, accepted: false)
    XCTAssertTrue(navigation.isActive)
    XCTAssertEqual(navigation.handle(control: .dpadUp, isPressed: true), .navigate(.up))

    XCTAssertEqual(navigation.handle(control: .b, isPressed: true), .navigate(.cancel))
    navigation.complete(.cancel, accepted: false)
    XCTAssertTrue(navigation.isActive)
  }

  func testPermissionMenuReleasesStaleCaptureWhenNativeMenuDisappears() {
    var navigation = PermissionMenuNavigationState()
    navigation.begin()

    navigation.refresh(menuIsVisible: false)

    XCTAssertFalse(navigation.isActive)
    XCTAssertEqual(navigation.handle(control: .x, isPressed: true), .passthrough)
  }

  func testPermissionMenuPassthroughDoesNotBlockBaseMappings() {
    var navigation = PermissionMenuNavigationState()
    navigation.begin()

    let decision = navigation.handle(control: .rt, isPressed: true)

    XCTAssertEqual(decision, .passthrough)
    XCTAssertFalse(decision.blocksBaseDispatch)
    XCTAssertTrue(PermissionMenuInputDecision.consume.blocksBaseDispatch)
    XCTAssertTrue(PermissionMenuInputDecision.navigate(.down).blocksBaseDispatch)
  }

  func testSuccessfulModelPickerAutomaticallyEntersTheFirstMenuItem() {
    XCTAssertEqual(ModelMenuActivationPlan.initialNavigation(openAccepted: true), .down)
    XCTAssertNil(ModelMenuActivationPlan.initialNavigation(openAccepted: false))
  }

  func testModelSubmenuTransitionRetriesBeforeEndingMenuNavigation() {
    XCTAssertEqual(
      ModelMenuTransitionPlan.decision(hasVisibleItems: false, attempt: 0),
      .retry(after: 0.10)
    )
    XCTAssertEqual(
      ModelMenuTransitionPlan.decision(hasVisibleItems: true, attempt: 2),
      .ready
    )
    XCTAssertEqual(
      ModelMenuTransitionPlan.decision(hasVisibleItems: false, attempt: 5),
      .finish
    )
  }

  func testModelMenuStateCanEndWhenThePickerFailsToOpen() {
    var navigation = ModelMenuNavigationState()
    navigation.begin()

    navigation.end()

    XCTAssertFalse(navigation.isActive)
    XCTAssertNil(navigation.handle(control: .dpadDown, isPressed: true))
  }

  func testStickGateTriggersOnceUntilTheStickReturnsToCenter() {
    var gate = StickGate(activationThreshold: 0.72, releaseThreshold: 0.3)

    XCTAssertEqual(gate.update(x: 0.9, y: 0.1), .right)
    XCTAssertNil(gate.update(x: 1.0, y: 0.0))
    XCTAssertNil(gate.update(x: 0.2, y: 0.1))
    XCTAssertEqual(gate.update(x: 0.0, y: -0.9), .down)
  }

  func testTriggerPressGateUsesHysteresisForAnalogValues() {
    var gate = TriggerPressGate(pressThreshold: 0.55, releaseThreshold: 0.3)

    XCTAssertNil(gate.update(value: 0.4))
    XCTAssertEqual(gate.update(value: 0.6), .pressed)
    XCTAssertNil(gate.update(value: 0.4))
    XCTAssertEqual(gate.update(value: 0.2), .released)
  }

  func testPushToTalkHoldStartsAndStopsOnRelease() {
    var machine = PushToTalkMachine(doubleTapWindow: 0.35)

    XCTAssertEqual(machine.handle(.press, at: 0.0), [.start])
    XCTAssertEqual(machine.handle(.release, at: 0.8), [.stop])
    XCTAssertEqual(machine.state, .idle)
  }

  func testPushToTalkQuickTapStopsAfterDoubleTapWindow() {
    var machine = PushToTalkMachine(doubleTapWindow: 0.35)

    XCTAssertEqual(machine.handle(.press, at: 0.0), [.start])
    XCTAssertEqual(machine.handle(.release, at: 0.1), [])
    XCTAssertEqual(machine.advance(to: 0.34), [])
    XCTAssertEqual(machine.advance(to: 0.36), [.stop])
    XCTAssertEqual(machine.state, .idle)
  }

  func testPushToTalkDoubleTapLatchesUntilNextPress() {
    var machine = PushToTalkMachine(doubleTapWindow: 0.35)

    XCTAssertEqual(machine.handle(.press, at: 0.0), [.start])
    XCTAssertEqual(machine.handle(.release, at: 0.1), [])
    XCTAssertEqual(machine.handle(.press, at: 0.2), [])
    XCTAssertEqual(machine.handle(.release, at: 0.25), [])
    XCTAssertEqual(machine.state, .latched)
    XCTAssertEqual(machine.handle(.press, at: 0.8), [.stop])
    XCTAssertEqual(machine.state, .suppressingPresses(until: 1.15))
    XCTAssertEqual(machine.handle(.release, at: 0.9), [])
    XCTAssertEqual(machine.advance(to: 1.16), [])
    XCTAssertEqual(machine.state, .idle)
  }

  func testDictationAccessibilityMatcherMatchesLocalizedComposerControls() {
    let chineseStart = AccessibilityControlMetadata(
      role: "AXButton",
      identifier: "",
      title: "",
      description: "听写",
      isEnabled: true,
      actions: ["AXPress"]
    )
    let englishStop = AccessibilityControlMetadata(
      role: "AXButton",
      identifier: "",
      title: "",
      description: "Stop dictation",
      isEnabled: true,
      actions: ["AXPress"]
    )

    XCTAssertTrue(DictationAccessibilityMatcher.matches(chineseStart, phase: .start))
    XCTAssertTrue(DictationAccessibilityMatcher.matches(englishStop, phase: .stop))
  }

  func testDictationAccessibilityMatcherRejectsAgentStopAndDisabledControls() {
    let agentStop = AccessibilityControlMetadata(
      role: "AXButton",
      identifier: "",
      title: "",
      description: "停止",
      isEnabled: true,
      actions: ["AXPress"]
    )
    let disabledDictation = AccessibilityControlMetadata(
      role: "AXButton",
      identifier: "",
      title: "",
      description: "听写",
      isEnabled: false,
      actions: ["AXPress"]
    )

    XCTAssertFalse(DictationAccessibilityMatcher.matches(agentStop, phase: .stop))
    XCTAssertFalse(DictationAccessibilityMatcher.matches(disabledDictation, phase: .start))
  }

  func testDictationAccessibilityMatcherUsesAnyExactAccessibleLabel() {
    let identifiedButton = AccessibilityControlMetadata(
      role: "AXButton",
      identifier: "composer-dictation",
      title: "",
      description: "听写",
      isEnabled: true,
      actions: ["AXPress"]
    )

    XCTAssertTrue(DictationAccessibilityMatcher.matches(identifiedButton, phase: .start))
  }

  func testLongPressGateFiresOnlyOnceAfterThreshold() {
    var gate = LongPressGate(duration: 0.6)

    gate.begin(at: 10.0)
    XCTAssertFalse(gate.update(at: 10.59))
    XCTAssertTrue(gate.update(at: 10.6))
    XCTAssertFalse(gate.update(at: 11.0))
    gate.cancel()
    XCTAssertFalse(gate.update(at: 12.0))
  }

  func testDefaultMappingContainsReliableDailyActions() throws {
    let config = MappingConfiguration.default

    XCTAssertEqual(
      config.layers,
      [
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
          "home": "launchCodex",
          GamepadControl.share.rawValue: "launchCodex",
        ],
        BridgeLayer.task.rawValue: [
          GamepadControl.rt.rawValue: "newTask",
          GamepadControl.a.rawValue: "selectionAddToTask",
          GamepadControl.b.rawValue: "cancel",
          GamepadControl.x.rawValue: "selectionAskSideChat",
          GamepadControl.y.rawValue: "selectionMoreDetails",
          GamepadControl.dpadUp.rawValue: "togglePin",
          GamepadControl.dpadLeft.rawValue: "previousTask",
          GamepadControl.dpadRight.rawValue: "nextTask",
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
      ]
    )

    let data = try JSONEncoder().encode(config)
    XCTAssertEqual(try JSONDecoder().decode(MappingConfiguration.self, from: data), config)
  }

  func testSystemLayerXStartsAStandaloneTaskOutsideAnyProject() {
    let system = MappingConfiguration.default.layers[BridgeLayer.system.rawValue]

    XCTAssertEqual(system?[GamepadControl.x.rawValue], "newProjectlessTask")
  }

  func testSystemLayerYStartsAProjectFromAFolder() {
    let system = MappingConfiguration.default.layers[BridgeLayer.system.rawValue]

    XCTAssertEqual(system?[GamepadControl.y.rawValue], "newProject")
  }

  func testNewProjectUsesCodexNativeOpenFolderMenu() throws {
    let action = try XCTUnwrap(ActionCatalog.definition(for: "newProject"))

    XCTAssertEqual(action.dispatch.kind, .nativeMenu)
    XCTAssertEqual(action.dispatch.menuPath, ["File", "Open Folder…"])
    XCTAssertFalse(action.isSafeForWebTest)
  }

  func testStandaloneTaskUsesTheInstalledCodexProjectlessShortcut() throws {
    let action = try XCTUnwrap(ActionCatalog.definition(for: "newProjectlessTask"))

    XCTAssertEqual(action.dispatch.kind, .keystroke)
    XCTAssertEqual(action.dispatch.key, "o")
    XCTAssertEqual(action.dispatch.modifiers, ["command", "option"])
    XCTAssertFalse(action.isSafeForWebTest)
  }

  func testLaunchCodexUsesTheDedicatedLaunchAction() throws {
    let action = try XCTUnwrap(ActionCatalog.definition(for: "launchCodex"))

    XCTAssertEqual(action.dispatch.kind, .uiControl)
    XCTAssertEqual(action.dispatch.uiControlID, "launchCodex")
    XCTAssertFalse(action.isSafeForWebTest)
  }

  func testDeveloperLayerUsesRTForExplicitCompletionNotification() {
    let config = MappingConfiguration.default

    XCTAssertEqual(
      config.layers[BridgeLayer.developer.rawValue]?[GamepadControl.rt.rawValue],
      "submitWithNotification"
    )
    XCTAssertNil(config.layers[BridgeLayer.developer.rawValue]?[GamepadControl.dpadLeft.rawValue])
    XCTAssertNil(config.layers[BridgeLayer.developer.rawValue]?[GamepadControl.dpadRight.rawValue])
    XCTAssertEqual(
      config.layers[BridgeLayer.base.rawValue]?[GamepadControl.rt.rawValue],
      "submit"
    )
  }

  func testSafetyLayerYOpensTheNativePermissionPicker() throws {
    let safety = MappingConfiguration.default.layers[BridgeLayer.safety.rawValue]
    let action = try XCTUnwrap(ActionCatalog.definition(for: "permissionPicker"))

    XCTAssertEqual(safety?[GamepadControl.y.rawValue], "permissionPicker")
    XCTAssertEqual(action.dispatch.kind, .uiControl)
    XCTAssertEqual(action.dispatch.uiControlID, "permissionPicker")
    XCTAssertFalse(action.isSafeForWebTest)
  }

  func testPermissionPickerMigrationAddsOnlyTheMissingSafetyYBinding() {
    var legacy = MappingConfiguration.default
    legacy.setAction(nil, for: .y, layer: .safety)
    legacy.setAction("review", for: .x, layer: .developer)

    let migrated = MappingConfigurationMigration.addingPermissionPickerIfMissing(to: legacy)

    XCTAssertEqual(migrated.action(for: .y, layer: .safety), "permissionPicker")
    XCTAssertEqual(migrated.action(for: .x, layer: .developer), "review")
  }

  func testPermissionPickerMigrationPreservesAnExistingCustomSafetyYBinding() {
    var custom = MappingConfiguration.default
    custom.setAction("review", for: .y, layer: .safety)

    let migrated = MappingConfigurationMigration.addingPermissionPickerIfMissing(to: custom)

    XCTAssertEqual(migrated.action(for: .y, layer: .safety), "review")
  }

  func testCompletionNotificationMigrationAddsOnlyTheMissingDeveloperRTBinding() {
    var legacy = MappingConfiguration.default
    legacy.setAction(nil, for: .rt, layer: .developer)
    legacy.setAction("review", for: .x, layer: .developer)

    let migrated = MappingConfigurationMigration.addingCompletionNotificationIfMissing(to: legacy)

    XCTAssertEqual(migrated.action(for: .rt, layer: .developer), "submitWithNotification")
    XCTAssertEqual(migrated.action(for: .x, layer: .developer), "review")
  }

  func testCompletionNotificationMigrationPreservesCustomDeveloperRTBinding() {
    var custom = MappingConfiguration.default
    custom.setAction("newTask", for: .rt, layer: .developer)

    let migrated = MappingConfigurationMigration.addingCompletionNotificationIfMissing(to: custom)

    XCTAssertEqual(migrated.action(for: .rt, layer: .developer), "newTask")
  }

  func testDefaultMappingUsesOnlyVerifiedDispatchKinds() throws {
    for (layer, mappings) in MappingConfiguration.default.layers {
      for (control, actionID) in mappings {
        let dispatch = try XCTUnwrap(ActionCatalog.definition(for: actionID)?.dispatch)
        if dispatch.kind == .uiControl {
          XCTAssertTrue(
            Set([
              "focusComposer", "composerMoveLeft", "composerMoveRight",
              "composerMoveLineStart", "composerMoveLineEnd", "composerSelectLeft",
              "composerSelectRight", "composerSelectLineStart", "composerSelectLineEnd",
              "composerDeleteBackward", "selectionAddToTask", "selectionAskSideChat",
              "selectionMoreDetails", "previousWindow", "nextWindow", "newTaskWindow",
              "windowSwitcher", "launchCodex", "modelPicker", "permissionPicker", "reasoningIncrease",
              "reasoningDecrease", "reasoningCycle", "fastToggle", "planToggle",
            ]).contains(actionID),
            "\(layer).\(control) uses unverified UI control action \(actionID)"
          )
          continue
        }
        XCTAssertTrue(
          [.pushToTalk, .plainKey, .nativeMenu, .keystroke].contains(dispatch.kind),
          "\(layer).\(control) uses unverified \(dispatch.kind.rawValue) action \(actionID)"
        )
      }
    }
  }

  func testActionCatalogHasUniqueIDsAndCoversEveryDefaultMapping() {
    let actions = ActionCatalog.all
    let ids = actions.map(\.id)
    let mappedIDs = MappingConfiguration.default.layers.values.flatMap(\.values)

    XCTAssertEqual(Set(ids).count, ids.count)
    XCTAssertTrue(Set(mappedIDs).isSubset(of: Set(ids)))
    XCTAssertEqual(ActionCatalog.definition(for: "pushToTalk")?.dispatch.kind, .pushToTalk)
  }

  func testModelPickerUsesTheRegisteredCodexKeyboardShortcut() {
    let dispatch = ActionCatalog.definition(for: "modelPicker")?.dispatch

    XCTAssertEqual(dispatch?.kind, .keystroke)
    XCTAssertEqual(dispatch?.key, "m")
    XCTAssertEqual(dispatch?.modifiers, ["control", "shift"])
    XCTAssertEqual(dispatch?.requiresShortcutSetup, false)
  }

  func testCoreModeActionsUseExplicitUIControls() {
    let expectedControls = [
      "reasoningIncrease", "reasoningDecrease", "reasoningCycle",
      "fastToggle", "planToggle", "review", "searchTasks", "addFiles", "addPhotos",
      "commandMenu", "focusComposer", "clearComposer", "composerMoveLeft",
      "composerMoveRight", "composerMoveLineStart", "composerMoveLineEnd",
      "composerSelectLeft", "composerSelectRight", "composerSelectLineStart",
      "composerSelectLineEnd", "composerDeleteBackward", "selectionAddToTask",
      "selectionAskSideChat", "selectionMoreDetails", "previousWindow", "nextWindow",
      "newTaskWindow", "windowSwitcher", "permissionPicker",
    ]

    for actionID in expectedControls {
      let dispatch = ActionCatalog.definition(for: actionID)?.dispatch
      XCTAssertEqual(dispatch?.kind, .uiControl, actionID)
      XCTAssertEqual(dispatch?.uiControlID, actionID, actionID)
      XCTAssertEqual(dispatch?.requiresShortcutSetup, false, actionID)
    }
  }

  func testProvenAppCommandsUseNativeMenuItems() {
    let expectedPaths = [
      "terminal": ["View", "Open Terminal"],
      "browser": ["View", "Open Browser Tab"],
      "toggleSidePanel": ["View", "Toggle Side Panel"],
      "toggleBottomPanel": ["View", "Toggle Bottom Panel"],
      "toggleSidebar": ["View", "Toggle Sidebar"],
      "openFolder": ["File", "Open Folder…"],
      "newProject": ["File", "Open Folder…"],
      "previousTask": ["View", "Previous Task"],
      "nextTask": ["View", "Next Task"],
      "newTask": ["File", "New Chat"],
      "newWindow": ["File", "New Window"],
      "navigateBack": ["View", "Back"],
      "navigateForward": ["View", "Forward"],
      "togglePin": ["View", "Toggle Pinned Summary"],
      "settings": ["ChatGPT", "Settings…"],
      "keyboardShortcuts": ["Help", "Keyboard Shortcuts"],
      "feedback": ["Help", "Send Feedback"],
    ]

    for (actionID, menuPath) in expectedPaths {
      let dispatch = ActionCatalog.definition(for: actionID)?.dispatch
      XCTAssertEqual(dispatch?.kind, .nativeMenu, actionID)
      XCTAssertEqual(dispatch?.menuPath, menuPath, actionID)
    }
  }

  func testPlainKeysAndUnavailableActionsAreHonest() {
    XCTAssertEqual(ActionCatalog.definition(for: "submit")?.dispatch.kind, .plainKey)
    XCTAssertEqual(ActionCatalog.definition(for: "cancel")?.dispatch.kind, .plainKey)

    for actionID in ["environmentAction1", "environmentAction2", "environmentAction9", "fork"] {
      let dispatch = ActionCatalog.definition(for: actionID)?.dispatch
      XCTAssertEqual(dispatch?.kind, .unavailable, actionID)
      XCTAssertFalse(dispatch?.unavailableReason?.isEmpty ?? true, actionID)
    }
  }

  func testPushToTalkUsesDirectAccessibilityControl() {
    let dispatch = ActionCatalog.definition(for: "pushToTalk")?.dispatch

    XCTAssertEqual(dispatch?.kind, .pushToTalk)
    XCTAssertNil(dispatch?.key)
    XCTAssertEqual(dispatch?.modifiers, [])
  }

  func testSafetyActionsCarryExplicitHoldDurations() {
    XCTAssertEqual(ActionCatalog.definition(for: "approve")?.holdDuration, 0.6)
    XCTAssertEqual(ActionCatalog.definition(for: "decline")?.holdDuration, 0.35)
    XCTAssertEqual(ActionCatalog.definition(for: "archiveTask")?.holdDuration, 0.8)
    XCTAssertNil(ActionCatalog.definition(for: "review")?.holdDuration)
  }

  func testMappingValidatorRejectsUnknownLayersControlsAndActions() {
    XCTAssertNoThrow(try MappingValidator.validate(.default))

    var unknownAction = MappingConfiguration.default
    unknownAction.layers["base"]?["a"] = "notARealAction"
    XCTAssertThrowsError(try MappingValidator.validate(unknownAction))

    var unknownControl = MappingConfiguration.default
    unknownControl.layers["base"]?["teleport"] = "review"
    XCTAssertThrowsError(try MappingValidator.validate(unknownControl))

    var unknownLayer = MappingConfiguration.default
    unknownLayer.layers["hidden"] = ["a": "review"]
    XCTAssertThrowsError(try MappingValidator.validate(unknownLayer))
  }

  func testHTTPRequestParserWaitsForBodyAndParsesCompleteRequest() throws {
    let incomplete = Data("POST /api/config HTTP/1.1\r\nContent-Length: 5\r\n\r\nabc".utf8)
    XCTAssertNil(try HTTPRequestParser.parse(incomplete))

    let complete = Data(
      "POST /api/config HTTP/1.1\r\nContent-Length: 5\r\nOrigin: http://127.0.0.1:8765\r\n\r\nabcde"
        .utf8)
    let request = try XCTUnwrap(HTTPRequestParser.parse(complete))
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.path, "/api/config")
    XCTAssertEqual(request.headers["origin"], "http://127.0.0.1:8765")
    XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "abcde")
  }

  func testHTTPRequestParserRejectsOversizedBodies() {
    let request = Data("POST /api/config HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n".utf8)
    XCTAssertThrowsError(try HTTPRequestParser.parse(request))
  }

  func testTapOrHoldGateSeparatesQuickReleaseFromLongHold() {
    var gate = TapOrHoldGate(duration: 0.5)
    gate.begin(at: 2.0)
    XCTAssertFalse(gate.update(at: 2.49))
    XCTAssertEqual(gate.end(at: 2.49), .tap)

    gate.begin(at: 4.0)
    XCTAssertTrue(gate.update(at: 4.5))
    XCTAssertEqual(gate.end(at: 4.7), .hold)
  }

  func testWebActionTestingBlocksSideEffects() {
    XCTAssertEqual(ActionCatalog.definition(for: "review")?.isSafeForWebTest, true)
    XCTAssertEqual(ActionCatalog.definition(for: "submit")?.isSafeForWebTest, false)
    XCTAssertEqual(ActionCatalog.definition(for: "pushToTalk")?.isSafeForWebTest, false)
    XCTAssertEqual(ActionCatalog.definition(for: "gitCommit")?.isSafeForWebTest, false)
    XCTAssertEqual(ActionCatalog.definition(for: "createPR")?.isSafeForWebTest, false)
    XCTAssertEqual(ActionCatalog.definition(for: "clearComposer")?.isSafeForWebTest, false)
    for actionID in [
      "composerMoveLeft", "composerMoveRight", "composerMoveLineStart", "composerMoveLineEnd",
      "composerSelectLeft", "composerSelectRight", "composerSelectLineStart",
      "composerSelectLineEnd", "composerDeleteBackward",
      "selectionAddToTask", "selectionAskSideChat", "selectionMoreDetails",
    ] {
      XCTAssertEqual(ActionCatalog.definition(for: actionID)?.isSafeForWebTest, false, actionID)
    }
    XCTAssertEqual(ActionCatalog.definition(for: "environmentAction1")?.isSafeForWebTest, false)
    XCTAssertEqual(ActionCatalog.definition(for: "approve")?.isSafeForWebTest, false)
  }
}
