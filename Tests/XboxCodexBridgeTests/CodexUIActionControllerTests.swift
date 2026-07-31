import CoreGraphics
import XCTest
import XboxCodexBridgeCore

@testable import XboxCodexBridge

final class CodexUIActionControllerTests: XCTestCase {
  func testPermissionPickerSelectorAcceptsCurrentChineseAndEnglishModesAtComposerBottom() {
    let candidates = [
      CodexPermissionPickerCandidateMetadata(
        role: "AXButton", label: "请求批准", relativeY: 0.44,
        isEnabled: true, supportsPress: true
      ),
      CodexPermissionPickerCandidateMetadata(
        role: "AXStaticText", label: "替我审批", relativeY: 0.88,
        isEnabled: true, supportsPress: true
      ),
      CodexPermissionPickerCandidateMetadata(
        role: "AXButton", label: "替我审批", relativeY: 0.86,
        isEnabled: true, supportsPress: true
      ),
      CodexPermissionPickerCandidateMetadata(
        role: "AXButton", label: "Full access", relativeY: 0.91,
        isEnabled: true, supportsPress: true
      ),
    ]

    XCTAssertEqual(CodexPermissionPickerSelector.candidateIndices(in: candidates), [2, 3])
    XCTAssertEqual(CodexPermissionPickerSelector.bestIndex(in: candidates), 3)
  }

  func testPermissionPickerSelectorRejectsDisabledOrApproximateConversationControls() {
    let candidates = [
      CodexPermissionPickerCandidateMetadata(
        role: "AXButton", label: "请求批准这项操作", relativeY: 0.90,
        isEnabled: true, supportsPress: true
      ),
      CodexPermissionPickerCandidateMetadata(
        role: "AXButton", label: "Approve for me", relativeY: 0.86,
        isEnabled: false, supportsPress: true
      ),
      CodexPermissionPickerCandidateMetadata(
        role: "AXButton", label: "Custom", relativeY: 0.83,
        isEnabled: true, supportsPress: false
      ),
    ]

    XCTAssertTrue(CodexPermissionPickerSelector.candidateIndices(in: candidates).isEmpty)
    XCTAssertNil(CodexPermissionPickerSelector.bestIndex(in: candidates))
  }

  func testPermissionPickerActivationReportsSuccessOnlyAfterPopupAppears() {
    var clickCount = 0

    XCTAssertEqual(
      CodexPermissionPickerActivation.resolve(
        pressOutcome: .success,
        isMenuVisible: { false },
        fallbackClick: {
          clickCount += 1
          return .success
        }
      ),
      .targetNotFound
    )
    XCTAssertEqual(clickCount, 1)

    XCTAssertEqual(
      CodexPermissionPickerActivation.resolve(
        pressOutcome: .success,
        isMenuVisible: { true },
        fallbackClick: {
          clickCount += 1
          return .success
        }
      ),
      .success
    )
    XCTAssertEqual(clickCount, 1)
  }

  func testPermissionMenuSelectorRecognizesOnlyTheNativePermissionMenu() {
    let candidates = [
      CodexPermissionMenuMetadata(
        role: "AXMenu", label: "GPT-5.6", actions: ["AXCancel"],
        itemLabels: ["模型", "推理强度"]
      ),
      CodexPermissionMenuMetadata(
        role: "AXMenu", label: "替我审批", actions: ["AXCancel"],
        itemLabels: [
          "请求批准 编辑外部文件和使用互联网时始终询问",
          "替我审批 仅对检测到的风险操作请求批准",
          "完全访问权限 可不受限制地访问互联网和您电脑上的任何文件",
          "自定义 (config.toml) 使用 config.toml 中定义的权限",
        ]
      ),
    ]

    XCTAssertEqual(CodexPermissionMenuSelector.bestIndex(in: candidates), 1)
  }

  func testPermissionMenuNavigationUsesTheDirectAccessibilityClient() {
    let client = FakeCodexUIActionClient()
    client.permissionNavigationOutcome = .success
    let controller = CodexUIActionController(client: client)
    let completed = expectation(description: "permission navigation completes")

    controller.performPermissionMenuNavigation(.down) { result in
      XCTAssertTrue(result.accepted)
      XCTAssertEqual(result.message, "Controlled the visible permission menu.")
      completed.fulfill()
    }

    wait(for: [completed], timeout: 2)
    XCTAssertEqual(client.permissionNavigations, [.down])
  }

  func testPermissionMenuVisibilityUsesTheDirectAccessibilityClient() {
    let client = FakeCodexUIActionClient()
    let controller = CodexUIActionController(client: client)

    client.permissionMenuVisible = true
    XCTAssertTrue(controller.isPermissionMenuVisible())

    client.permissionMenuVisible = false
    XCTAssertFalse(controller.isPermissionMenuVisible())
  }

  func testCustomModelMenuItemUsesPointerClickInsteadOfAXPress() {
    XCTAssertEqual(
      CodexModelMenuItemActivation.preferredRoute,
      .pointerClick
    )
  }

  func testPermissionMenuItemUsesPointerClickInsteadOfAXPress() {
    XCTAssertEqual(
      CodexPermissionMenuItemActivation.preferredRoute,
      .pointerClick
    )
  }

  func testPermissionMenuCancelFallsBackToEscapeWhenAXCancelLeavesMenuVisible() {
    var escapeCount = 0

    let outcome = CodexPermissionMenuCancellation.resolve(
      menuIsStillVisible: true,
      fallbackEscape: {
        escapeCount += 1
        return true
      }
    )

    XCTAssertEqual(outcome, .success)
    XCTAssertEqual(escapeCount, 1)
  }

  func testPermissionMenuCancelDoesNotPostEscapeAfterMenuCloses() {
    var escapeCount = 0

    let outcome = CodexPermissionMenuCancellation.resolve(
      menuIsStillVisible: false,
      fallbackEscape: {
        escapeCount += 1
        return true
      }
    )

    XCTAssertEqual(outcome, .success)
    XCTAssertEqual(escapeCount, 0)
  }

  func testModelPickerFallsBackToPointerClickWhenShowMenuAndPressAreRejected() {
    var pressCount = 0
    var clickCount = 0

    let outcome = CodexModelPickerActivation.resolve(
      showMenuSucceeded: false,
      isMenuVisible: { false },
      fallbackPress: {
        pressCount += 1
        return .actionFailed
      },
      fallbackClick: {
        clickCount += 1
        return .success
      }
    )

    XCTAssertEqual(outcome, .success)
    XCTAssertEqual(pressCount, 1)
    XCTAssertEqual(clickCount, 1)
  }

  func testModelPickerUsesNativePressWhenShowMenuReportsFalseSuccess() {
    var pressCount = 0
    var clickCount = 0
    var isMenuVisible = false

    let outcome = CodexModelPickerActivation.resolve(
      showMenuSucceeded: true,
      isMenuVisible: { isMenuVisible },
      fallbackPress: {
        pressCount += 1
        isMenuVisible = true
        return .success
      },
      fallbackClick: {
        clickCount += 1
        return .success
      }
    )

    XCTAssertEqual(outcome, .success)
    XCTAssertEqual(pressCount, 1)
    XCTAssertEqual(clickCount, 0)
  }

  func testModelPickerDoesNotClickAgainWhenMenuIsVisible() {
    var pressCount = 0
    var clickCount = 0

    let outcome = CodexModelPickerActivation.resolve(
      showMenuSucceeded: true,
      isMenuVisible: { true },
      fallbackPress: {
        pressCount += 1
        return .success
      },
      fallbackClick: {
        clickCount += 1
        return .success
      }
    )

    XCTAssertEqual(outcome, .success)
    XCTAssertEqual(pressCount, 0)
    XCTAssertEqual(clickCount, 0)
  }

  func testModelPickerDiagnosticsKeepOnlyLowerPopupControls() {
    let candidates = [
      CodexModelPickerCandidateMetadata(
        role: "AXButton", label: "Send", identifier: "", value: "",
        relativeX: 0.92, relativeY: 0.90, isEnabled: true,
        supportsShowMenu: false, supportsPress: true
      ),
      CodexModelPickerCandidateMetadata(
        role: "AXPopUpButton", label: "Window", identifier: "", value: "",
        relativeX: 0.90, relativeY: 0.20, isEnabled: true,
        supportsShowMenu: true, supportsPress: true
      ),
      CodexModelPickerCandidateMetadata(
        role: "AXPopUpButton", label: "GPT-5", identifier: "model", value: "GPT-5",
        relativeX: 0.56, relativeY: 0.84, isEnabled: true,
        supportsShowMenu: true, supportsPress: true
      ),
    ]

    XCTAssertEqual(CodexModelPickerDiagnosticsSelector.candidateIndices(in: candidates), [2])
  }

  func testVisibleMenuItemSelectorKeepsOnlyEnabledPressableEntries() {
    let items = [
      CodexVisibleMenuItemMetadata(
        role: "AXMenuItem", label: "极高", isEnabled: true, supportsPress: true
      ),
      CodexVisibleMenuItemMetadata(
        role: "AXMenuItem", label: "高", isEnabled: false, supportsPress: true
      ),
      CodexVisibleMenuItemMetadata(
        role: "AXButton", label: "中", isEnabled: true, supportsPress: true
      ),
      CodexVisibleMenuItemMetadata(
        role: "AXStaticText", label: "低", isEnabled: true, supportsPress: true
      ),
      CodexVisibleMenuItemMetadata(
        role: "AXMenuItem", label: "低", isEnabled: true, supportsPress: false
      ),
    ]

    XCTAssertEqual(CodexVisibleMenuItemSelector.candidateIndices(in: items), [0, 2])
  }

  func testModelOverlayDiagnosticsKeepVisibleInteractiveAndLabeledElements() {
    let elements = [
      CodexModelOverlayElementMetadata(
        role: "AXButton", label: "GPT-5.6", value: "", identifier: "model-option",
        relativeX: 0.4, relativeY: 0.5, width: 180, height: 32,
        actions: ["AXPress"]
      ),
      CodexModelOverlayElementMetadata(
        role: "AXStaticText", label: "中", value: "", identifier: "",
        relativeX: 0.6, relativeY: 0.6, width: 40, height: 20,
        actions: []
      ),
      CodexModelOverlayElementMetadata(
        role: "AXGroup", label: "", value: "", identifier: "",
        relativeX: 0.2, relativeY: 0.3, width: 0, height: 0,
        actions: []
      ),
    ]

    XCTAssertEqual(CodexModelOverlayDiagnosticsSelector.candidateIndices(in: elements), [0, 1])
  }

  func testPopupSelectorRecognizesCodexCustomCancelableGroup() {
    let candidates = [
      CodexPopupContainerMetadata(
        role: "AXMenu", actions: ["AXCancel"], pressableMenuItemCount: 12,
        relativeY: 0.15, width: 420, height: 600
      ),
      CodexPopupContainerMetadata(
        role: "AXGroup", actions: ["AXShowMenu"], pressableMenuItemCount: 0,
        relativeY: 0, width: 2_560, height: 1_440
      ),
      CodexPopupContainerMetadata(
        role: "AXGroup", actions: ["AXShowMenu", "AXCancel"],
        pressableMenuItemCount: 4, relativeY: 0.81, width: 314, height: 188
      ),
    ]

    XCTAssertEqual(CodexPopupContainerSelector.bestIndex(in: candidates), 2)
  }

  func testPopupSelectorUsesTheSmallestPopupWhenSubmenuIsNested() {
    let candidates = [
      CodexPopupContainerMetadata(
        role: "AXGroup", actions: ["AXShowMenu", "AXCancel"],
        pressableMenuItemCount: 9, relativeY: 0.52, width: 360, height: 420
      ),
      CodexPopupContainerMetadata(
        role: "AXGroup", actions: ["AXShowMenu", "AXCancel"],
        pressableMenuItemCount: 4, relativeY: 0.58, width: 280, height: 210
      ),
    ]

    XCTAssertEqual(CodexPopupContainerSelector.bestIndex(in: candidates), 1)
  }

  func testPopupSelectorRejectsUnrelatedNativeMenusWithoutTheModelGroup() {
    let candidates = [
      CodexPopupContainerMetadata(
        role: "AXMenu", actions: ["AXCancel"], pressableMenuItemCount: 12,
        relativeY: 0.15, width: 420, height: 600
      )
    ]

    XCTAssertNil(CodexPopupContainerSelector.bestIndex(in: candidates))
  }

  func testModelMenuSelectionMovesWithinVisibleItemsWithoutWrapping() {
    XCTAssertEqual(
      CodexModelMenuSelection.destinationIndex(current: nil, count: 4, step: 1),
      0
    )
    XCTAssertEqual(
      CodexModelMenuSelection.destinationIndex(current: 0, count: 4, step: 1),
      1
    )
    XCTAssertEqual(
      CodexModelMenuSelection.destinationIndex(current: 3, count: 4, step: 1),
      3
    )
    XCTAssertEqual(
      CodexModelMenuSelection.destinationIndex(current: 0, count: 4, step: -1),
      0
    )
    XCTAssertNil(CodexModelMenuSelection.destinationIndex(current: nil, count: 0, step: 1))
  }

  func testWindowSelectorPrefersLargestNonDictationWindow() {
    let windows = [
      CodexWindowMetadata(
        title: "Dictation", size: CGSize(width: 720, height: 84), isFocused: true,
        isMain: false),
      CodexWindowMetadata(
        title: "ChatGPT", size: CGSize(width: 2_560, height: 1_440), isFocused: false,
        isMain: false),
      CodexWindowMetadata(
        title: "Settings", size: CGSize(width: 900, height: 700), isFocused: false,
        isMain: false),
    ]

    XCTAssertEqual(CodexWindowSelector.bestIndex(in: windows), 1)
  }

  func testWindowSelectorRejectsDictationOverlayAsOnlyWindow() {
    let windows = [
      CodexWindowMetadata(
        title: "Dictation", size: CGSize(width: 720, height: 84), isFocused: true,
        isMain: false)
    ]

    XCTAssertNil(CodexWindowSelector.bestIndex(in: windows))
  }

  func testWindowSelectorPrefersLastFocusedCodexWindowOverLargerWindow() {
    let windows = [
      CodexWindowMetadata(
        title: "ChatGPT", size: CGSize(width: 2_560, height: 1_440), isFocused: false,
        isMain: false),
      CodexWindowMetadata(
        title: "ChatGPT", size: CGSize(width: 1_920, height: 1_050), isFocused: true,
        isMain: true),
    ]

    XCTAssertEqual(CodexWindowSelector.bestIndex(in: windows), 1)
  }

  func testWindowSelectorUsesMainWindowWhenDictationOwnsFocus() {
    let windows = [
      CodexWindowMetadata(
        title: "Dictation", size: CGSize(width: 720, height: 84), isFocused: true,
        isMain: false),
      CodexWindowMetadata(
        title: "ChatGPT", size: CGSize(width: 1_920, height: 1_050), isFocused: false,
        isMain: true),
      CodexWindowMetadata(
        title: "ChatGPT", size: CGSize(width: 2_560, height: 1_440), isFocused: false,
        isMain: false),
    ]

    XCTAssertEqual(CodexWindowSelector.bestIndex(in: windows), 1)
  }

  func testWindowTitleSelectorUsesTheTopContentHeaderInsteadOfSidebarText() {
    let candidates = [
      CodexWindowTitleCandidate(text: "新建任务", relativeX: 0.03, relativeY: 0.12),
      CodexWindowTitleCandidate(text: "codewhale contribute", relativeX: 0.23, relativeY: 0.02),
      CodexWindowTitleCandidate(text: "已安排", relativeX: 0.03, relativeY: 0.16),
    ]

    XCTAssertEqual(CodexWindowTitleSelector.bestTitle(in: candidates), "codewhale contribute")
  }

  func testWindowCycleWrapsInBothDirections() {
    XCTAssertEqual(CodexWindowCycleSelector.destinationIndex(current: 2, count: 3, step: 1), 0)
    XCTAssertEqual(CodexWindowCycleSelector.destinationIndex(current: 0, count: 3, step: -1), 2)
    XCTAssertNil(CodexWindowCycleSelector.destinationIndex(current: nil, count: 0, step: 1))
  }

  func testWindowMenuSelectorKeepsOnlyEnabledWindowEntries() {
    let items = [
      CodexWindowMenuItemMetadata(
        role: "AXMenuItem", identifier: "minimize:", isEnabled: true, isCurrent: false),
      CodexWindowMenuItemMetadata(
        role: "AXMenuItem", identifier: "makeKeyAndOrderFront:", isEnabled: true,
        isCurrent: true),
      CodexWindowMenuItemMetadata(
        role: "AXMenuItem", identifier: "makeKeyAndOrderFront:", isEnabled: false,
        isCurrent: false),
      CodexWindowMenuItemMetadata(
        role: "AXButton", identifier: "makeKeyAndOrderFront:", isEnabled: true,
        isCurrent: false),
      CodexWindowMenuItemMetadata(
        role: "AXMenuItem", identifier: "makeKeyAndOrderFront:", isEnabled: true,
        isCurrent: false),
    ]

    XCTAssertEqual(CodexWindowMenuSelector.candidateIndices(in: items), [1, 4])
    XCTAssertEqual(CodexWindowMenuSelector.currentCandidateIndex(in: items), 0)
  }

  func testWindowSwitcherStateStartsAtCurrentAndWraps() {
    var state = WindowSwitcherState(count: 4, currentIndex: 2)

    XCTAssertEqual(state.selectedIndex, 2)
    state.move(step: 1)
    XCTAssertEqual(state.selectedIndex, 3)
    state.move(step: 1)
    XCTAssertEqual(state.selectedIndex, 0)
    state.move(step: -1)
    XCTAssertEqual(state.selectedIndex, 3)
  }

  func testWindowTitleHistoryResetsWhenTheGlobalWindowListChanges() {
    var history = CodexWindowTitleHistory()
    history.synchronize(windowCount: 3)
    history.record("当前对话", at: 0)
    history.synchronize(windowCount: 3)
    XCTAssertEqual(history[0], "当前对话")

    history.synchronize(windowCount: 2)
    XCTAssertNil(history[0])
  }

  func testWindowSwitcherASelectsTheHighlightedEntryBeforeDismissing() {
    let controller = WindowSwitcherController()
    let entries = [
      CodexWindowMenuEntry(id: "window-menu-0", title: "窗口 1", isCurrent: false),
      CodexWindowMenuEntry(id: "window-menu-1", title: "窗口 2", isCurrent: true),
    ]
    var selected: CodexWindowMenuEntry?
    controller.present(entries: entries) { selected = $0 }

    XCTAssertTrue(controller.handle(control: .a, isPressed: true))

    XCTAssertEqual(selected, entries[1])
    XCTAssertFalse(controller.isPresented)
  }

  func testProjectDeepLinkUsesTheChosenAbsoluteFolderWithoutADefaultRoot() throws {
    let folder = URL(fileURLWithPath: "/tmp/独立 项目", isDirectory: true)

    let url = try XCTUnwrap(CodexProjectDeepLink.url(for: folder))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(components.scheme, "codex")
    XCTAssertEqual(components.host, "threads")
    XCTAssertEqual(components.path, "/new")
    XCTAssertEqual(components.queryItems, [URLQueryItem(name: "path", value: folder.path)])
  }

  func testOutputSelectionActionsExposeExactLocalizedToolbarLabels() {
    XCTAssertEqual(
      OutputSelectionControl(rawValue: "selectionAddToTask")?.labels,
      ["添加到任务", "Add to task"]
    )
    XCTAssertEqual(
      OutputSelectionControl(rawValue: "selectionAskSideChat")?.labels,
      ["在侧边聊天中提问", "Ask in side chat"]
    )
    XCTAssertEqual(
      OutputSelectionControl(rawValue: "selectionMoreDetails")?.labels,
      ["更多详情", "More details"]
    )
  }

  func testToolbarControlSelectorRejectsPartialOrDisabledMatches() {
    let candidates = [
      CodexToolbarControlMetadata(
        role: "AXButton", label: "更多详情选项", isEnabled: true, supportsPress: true),
      CodexToolbarControlMetadata(
        role: "AXButton", label: "更多详情", isEnabled: false, supportsPress: true),
      CodexToolbarControlMetadata(
        role: "AXButton", label: "更多详情", isEnabled: true, supportsPress: false),
      CodexToolbarControlMetadata(
        role: "AXButton", label: "更多详情", isEnabled: true, supportsPress: true),
    ]

    XCTAssertEqual(
      CodexToolbarControlSelector.bestIndex(in: candidates, labels: ["更多详情"]),
      3
    )
  }

  func testWindowControllerListsAndFocusesWindowCapableClient() {
    let client = FakeCodexUIActionClient()
    client.windows = [
      CodexWindowInfo(id: "abc", title: "任务 A", isFocused: true),
      CodexWindowInfo(id: "def", title: "任务 B", isFocused: false),
    ]
    let controller = CodexUIActionController(client: client)

    XCTAssertEqual(controller.codexWindows(), client.windows)
    XCTAssertTrue(controller.focusCodexWindow(id: "def"))
    XCTAssertEqual(client.focusedWindowIDs, ["def"])
  }

  func testComposerSelectorPrefersFocusedWritableComposerOverBrowserTextArea() {
    let candidates = [
      CodexComposerMetadata(
        role: "AXTextArea", title: "What deserves your full attention?", isEnabled: true,
        isFocused: false, isValueSettable: true, relativeY: 0.82),
      CodexComposerMetadata(
        role: "AXTextArea", title: "", isEnabled: true, isFocused: true,
        isValueSettable: true, relativeY: 0.84),
    ]

    XCTAssertEqual(CodexComposerSelector.bestIndex(in: candidates), 1)
  }

  func testComposerSelectorRejectsUntitledTextAreaOutsideComposerRegion() {
    let candidates = [
      CodexComposerMetadata(
        role: "AXTextArea", title: "", isEnabled: true, isFocused: true,
        isValueSettable: true, relativeY: 0.3)
    ]

    XCTAssertNil(CodexComposerSelector.bestIndex(in: candidates))
  }

  func testR3GestureKeepsTapConfigurableAndRoutesHoldToClear() {
    XCTAssertNil(R3GestureActionRouter.actionID(for: .tap))
    XCTAssertEqual(R3GestureActionRouter.actionID(for: .hold), "clearComposer")
    XCTAssertNil(R3GestureActionRouter.actionID(for: .cancelled))
  }

  func testComposerTextEditorMovesAcrossWholeComposedCharacters() {
    let afterEmoji = ComposerTextState(
      text: "A😀中",
      selection: NSRange(location: 3, length: 0)
    )

    let movedLeft = ComposerTextEditor.apply(.moveLeft, to: afterEmoji)
    let movedRight = ComposerTextEditor.apply(.moveRight, to: movedLeft)

    XCTAssertEqual(movedLeft.selection, NSRange(location: 1, length: 0))
    XCTAssertEqual(movedRight.selection, NSRange(location: 3, length: 0))
    XCTAssertEqual(movedRight.text, "A😀中")
  }

  func testComposerTextEditorMovesToCurrentLineBoundaries() {
    let middleOfSecondLine = ComposerTextState(
      text: "one\n第二行\nthree",
      selection: NSRange(location: 6, length: 0)
    )

    XCTAssertEqual(
      ComposerTextEditor.apply(.moveToLineStart, to: middleOfSecondLine).selection,
      NSRange(location: 4, length: 0)
    )
    XCTAssertEqual(
      ComposerTextEditor.apply(.moveToLineEnd, to: middleOfSecondLine).selection,
      NSRange(location: 7, length: 0)
    )
  }

  func testComposerTextEditorSelectsAndDeletesOnlyTheChosenText() {
    var state = ComposerTextState(
      text: "A😀中Z",
      selection: NSRange(location: 4, length: 0)
    )

    state = ComposerTextEditor.apply(.selectLeft, to: state)
    state = ComposerTextEditor.apply(.selectLeft, to: state)
    state = ComposerTextEditor.apply(.deleteBackward, to: state)

    XCTAssertEqual(state.text, "AZ")
    XCTAssertEqual(state.selection, NSRange(location: 1, length: 0))
  }

  func testComposerTextEditorSelectsOneWholeCharacterToTheRight() {
    let beforeEmoji = ComposerTextState(
      text: "A😀中",
      selection: NSRange(location: 1, length: 0)
    )

    let selected = ComposerTextEditor.apply(.selectRight, to: beforeEmoji)

    XCTAssertEqual(selected.selection, NSRange(location: 1, length: 2))
  }

  func testComposerTextEditorSelectsToCurrentLineBoundaries() {
    let middleOfSecondLine = ComposerTextState(
      text: "one\n第二行\nthree",
      selection: NSRange(location: 5, length: 0)
    )

    XCTAssertEqual(
      ComposerTextEditor.apply(.selectToLineStart, to: middleOfSecondLine).selection,
      NSRange(location: 4, length: 1)
    )
    XCTAssertEqual(
      ComposerTextEditor.apply(.selectToLineEnd, to: middleOfSecondLine).selection,
      NSRange(location: 5, length: 2)
    )
  }

  func testComposerTextEditorDeleteBackwardRemovesOneWholeCharacterWithoutSelection() {
    let state = ComposerTextState(
      text: "A😀中",
      selection: NSRange(location: 3, length: 0)
    )

    let edited = ComposerTextEditor.apply(.deleteBackward, to: state)

    XCTAssertEqual(edited.text, "A中")
    XCTAssertEqual(edited.selection, NSRange(location: 1, length: 0))
  }

  func testNativeMenuSuccessReportsOnlyAfterClientConfirmsPress() {
    let client = FakeCodexUIActionClient()
    client.outcome = .success
    let controller = CodexUIActionController(client: client)

    let result = perform(ActionCatalog.definition(for: "toggleSidebar")!, with: controller)

    XCTAssertTrue(result.accepted)
    XCTAssertEqual(result.message, "Opened Toggle sidebar.")
    XCTAssertEqual(client.performedActionIDs, ["toggleSidebar"])
  }

  func testColdLaunchRetriesPermissionPickerUntilComposerControlsAreReady() {
    let client = FakeCodexUIActionClient()
    client.outcomes = [.targetNotFound, .targetNotFound, .success]
    let controller = CodexUIActionController(
      client: client,
      readinessAttempts: 3,
      readinessInterval: 0,
      sleep: { _ in }
    )

    let result = perform(ActionCatalog.definition(for: "permissionPicker")!, with: controller)

    XCTAssertTrue(result.accepted)
    XCTAssertEqual(
      client.performedActionIDs,
      ["permissionPicker", "permissionPicker", "permissionPicker"]
    )
  }

  func testColdLaunchWaitsForCodexProcessBeforePerformingUIAction() {
    let client = FakeCodexUIActionClient()
    client.activateResults = [false, false, true]
    client.outcome = .success
    let controller = CodexUIActionController(
      client: client,
      readinessAttempts: 3,
      readinessInterval: 0,
      sleep: { _ in }
    )

    let result = perform(ActionCatalog.definition(for: "permissionPicker")!, with: controller)

    XCTAssertTrue(result.accepted)
    XCTAssertEqual(client.activateCallCount, 3)
    XCTAssertEqual(client.performedActionIDs, ["permissionPicker"])
  }

  func testNewTaskWindowCreatesAWindowThenStartsAndFocusesANewTask() {
    let client = FakeCodexUIActionClient()
    client.windows = [CodexWindowInfo(id: "old", title: "任务 1", isFocused: true)]
    client.performHandler = { action in
      if action.id == "newWindow" {
        client.windows = [
          CodexWindowInfo(id: "new", title: "新窗口", isFocused: true),
          CodexWindowInfo(id: "old", title: "任务 1", isFocused: false),
        ]
      }
      return .success
    }
    let controller = CodexUIActionController(client: client)
    let action = ActionDefinition(
      id: "newTaskWindow",
      label: "New task window",
      category: "Navigation",
      dispatch: DispatchRecipe(kind: .uiControl, uiControlID: "newTaskWindow")
    )

    let result = perform(action, with: controller)

    XCTAssertTrue(result.accepted)
    XCTAssertEqual(client.performedActionIDs, ["newWindow", "newTask", "focusComposer"])
    XCTAssertEqual(client.focusedWindowIDs, ["new"])
  }

  func testNewTaskWindowWaitsUntilTheNewWindowIsActuallyFocused() {
    let client = FakeCodexUIActionClient()
    var created = false
    var focusRequested = false
    var focusChecks = 0
    client.codexWindowsHandler = {
      guard created else {
        return [CodexWindowInfo(id: "old", title: "任务 1", isFocused: true)]
      }
      guard focusRequested else {
        return [
          CodexWindowInfo(id: "new", title: "新窗口", isFocused: false),
          CodexWindowInfo(id: "old", title: "任务 1", isFocused: true),
        ]
      }
      focusChecks += 1
      let focusSettled = focusChecks >= 3
      return [
        CodexWindowInfo(id: "new", title: "新窗口", isFocused: focusSettled),
        CodexWindowInfo(id: "old", title: "任务 1", isFocused: !focusSettled),
      ]
    }
    client.focusHandler = { id in
      focusRequested = id == "new"
      return focusRequested
    }
    client.performHandler = { action in
      if action.id == "newWindow" { created = true }
      if action.id == "newTask", focusChecks < 3 { return .actionFailed }
      return .success
    }
    let controller = CodexUIActionController(client: client)

    let result = perform(ActionCatalog.definition(for: "newTaskWindow")!, with: controller)

    XCTAssertTrue(result.accepted)
    XCTAssertGreaterThanOrEqual(focusChecks, 3)
    XCTAssertEqual(client.performedActionIDs, ["newWindow", "newTask", "focusComposer"])
  }

  func testMissingTargetIsReportedWithoutClaimingTheActionWasSent() {
    let client = FakeCodexUIActionClient()
    client.outcome = .targetNotFound
    let controller = CodexUIActionController(client: client, readinessAttempts: 1)

    let result = perform(ActionCatalog.definition(for: "toggleSidebar")!, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(result.message, "Codex control unavailable: Toggle sidebar")
  }

  func testUnsupportedRouteIsReportedHonestly() {
    let client = FakeCodexUIActionClient()
    client.outcome = .unsupported("No stable control was found")
    let controller = CodexUIActionController(client: client)

    let result = perform(ActionCatalog.definition(for: "modelPicker")!, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(
      result.message,
      "Unsupported Codex UI route for Open model & reasoning: No stable control was found"
    )
  }

  func testActivationFailureIsReportedBeforeAttemptingTheAction() {
    let client = FakeCodexUIActionClient()
    client.activateResult = false
    let controller = CodexUIActionController(client: client, readinessAttempts: 1)

    let result = perform(ActionCatalog.definition(for: "toggleSidebar")!, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(result.message, "Codex App is not installed")
    XCTAssertTrue(client.performedActionIDs.isEmpty)
  }

  func testAccessibilityFailureShortCircuitsTheClient() {
    let client = FakeCodexUIActionClient()
    client.isTrusted = false
    let controller = CodexUIActionController(client: client)

    let result = perform(ActionCatalog.definition(for: "toggleSidebar")!, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(
      result.message,
      "Enable Accessibility for the bridge before sending Codex commands"
    )
    XCTAssertTrue(client.performedActionIDs.isEmpty)
  }

  func testUnavailableActionDoesNotCallTheUIClient() {
    let client = FakeCodexUIActionClient()
    let controller = CodexUIActionController(client: client)
    let action = ActionCatalog.definition(for: "fork")!

    let result = perform(action, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(result.message, "No verified Codex UI adapter is configured")
    XCTAssertTrue(client.performedActionIDs.isEmpty)
  }

  private func perform(
    _ action: ActionDefinition,
    with controller: CodexUIActionController
  ) -> DispatchResult {
    let expectation = expectation(description: "action result")
    var captured: DispatchResult?
    controller.perform(action) { result in
      captured = result
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2)
    return captured ?? DispatchResult(accepted: false, message: "missing result")
  }
}

private final class FakeCodexUIActionClient: CodexUIActionClient, CodexWindowClient,
  CodexPermissionMenuNavigationClient, CodexPermissionMenuVisibilityClient
{
  var isTrusted = true
  var activateResult = true
  var activateResults: [Bool] = []
  var activateCallCount = 0
  var outcome = CodexUIActionOutcome.targetNotFound
  var outcomes: [CodexUIActionOutcome] = []
  var performedActionIDs: [String] = []
  var windows: [CodexWindowInfo] = []
  var focusedWindowIDs: [String] = []
  var performHandler: ((ActionDefinition) -> CodexUIActionOutcome)?
  var codexWindowsHandler: (() -> [CodexWindowInfo])?
  var focusHandler: ((String) -> Bool)?
  var permissionNavigationOutcome = CodexUIActionOutcome.targetNotFound
  var permissionNavigations: [ModelMenuNavigationAction] = []
  var permissionMenuVisible = false

  func activateCodex() -> Bool {
    activateCallCount += 1
    return activateResults.isEmpty ? activateResult : activateResults.removeFirst()
  }

  func perform(_ action: ActionDefinition) -> CodexUIActionOutcome {
    performedActionIDs.append(action.id)
    if let performHandler { return performHandler(action) }
    return outcomes.isEmpty ? outcome : outcomes.removeFirst()
  }

  func codexWindows() -> [CodexWindowInfo] {
    codexWindowsHandler?() ?? windows
  }

  func focusCodexWindow(id: String) -> Bool {
    focusedWindowIDs.append(id)
    return focusHandler?(id) ?? windows.contains { $0.id == id }
  }

  func performPermissionMenuNavigation(
    _ navigation: ModelMenuNavigationAction
  ) -> CodexUIActionOutcome {
    permissionNavigations.append(navigation)
    return permissionNavigationOutcome
  }

  func isPermissionMenuVisible() -> Bool {
    permissionMenuVisible
  }
}
