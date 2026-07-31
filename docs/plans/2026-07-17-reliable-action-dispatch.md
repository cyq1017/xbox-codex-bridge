# Reliable Codex Action Dispatch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace unreliable synthetic modifier shortcuts with verified native-menu and focused-window UI control dispatch, then validate every Xbox mapping without falsely reporting success.

**Architecture:** Keep GameController input, layers, gestures, the local HTTP server, and the mapping UI unchanged. Route actions through three explicit backends: plain unmodified keys for proven composer primitives, exact Codex native menu items for app commands, and focused-window accessibility geometry clicks for React/Composer controls. Preserve unsupported and context-only action IDs, but return a clear unavailable/configuration result instead of `Sent`.

**Tech Stack:** Swift 6, AppKit, ApplicationServices AXUIElement, CoreGraphics, XCTest, vanilla HTML/JavaScript.

**Repository note:** This output directory is not a Git repository. Execute in place with red-green TDD, code review, and fresh build/runtime evidence; omit worktree and commit steps.

---

### Task 1: Encode honest dispatch capabilities

**Files:**
- Modify: `Sources/XboxCodexBridgeCore/ActionCatalog.swift`
- Modify: `Tests/XboxCodexBridgeCoreTests/BridgeCoreTests.swift`

**Steps:**

1. Write failing tests for `nativeMenu`, `uiControl`, `plainKey`, and `unavailable` dispatch recipes.
2. Assert native-menu mappings for Toggle Sidebar, Terminal, Browser, task navigation, Settings, Keyboard Shortcuts, and Feedback.
3. Assert reserved environment actions remain visible but are marked unavailable until explicitly configured.
4. Run focused tests and confirm the expected failures.
5. Add the smallest Codable recipe fields and catalog mappings needed to pass.
6. Re-run focused tests.

### Task 2: Add a tested native Codex menu controller

**Files:**
- Create: `Sources/XboxCodexBridge/CodexNativeMenuController.swift`
- Create: `Tests/XboxCodexBridgeTests/CodexNativeMenuControllerTests.swift`

**Steps:**

1. Write failing tests against an injected client for success, missing menu, disabled item, and failed invocation.
2. Run the focused tests and confirm RED.
3. Implement exact menu-bar and menu-item lookup with bounded AX traversal and `AXPress`.
4. Return action-specific errors; never report success solely because an event was posted.
5. Run focused tests and confirm GREEN.
6. Live-probe `View → Toggle Sidebar`, restore the sidebar, and record the result.

### Task 3: Generalize focused-window control clicking

**Files:**
- Modify: `Sources/XboxCodexBridge/CodexDictationController.swift`
- Create: `Sources/XboxCodexBridgeCore/CodexUIControl.swift`
- Modify: `Tests/XboxCodexBridgeTests/CodexDictationControllerTests.swift`
- Modify: `Tests/XboxCodexBridgeCoreTests/BridgeCoreTests.swift`

**Steps:**

1. Write failing tests that lookup targets the focused ChatGPT window, not the first matching window.
2. Write matcher tests for Search, Add files, Dictation, Model/reasoning, and Mode controls using exact roles and localized labels.
3. Confirm RED.
4. Refactor the shared pointer clicker and bounded focused-window lookup.
5. Preserve exact Dictation/Stop dictation matching and state verification.
6. Confirm focused tests pass.

### Task 4: Restore Base-layer actions

**Files:**
- Create: `Sources/XboxCodexBridge/CodexComposerController.swift`
- Create: `Tests/XboxCodexBridgeTests/CodexComposerControllerTests.swift`
- Modify: `Sources/XboxCodexBridge/BridgeRuntime.swift`
- Modify: `Sources/XboxCodexBridgeCore/ActionCatalog.swift`

**Steps:**

1. Write failing controller tests for opening Search/control UI, model/reasoning UI, Fast, Plan, and Review.
2. Probe idle Codex popovers to record exact English/Chinese option labels before implementing selectors.
3. Implement one action at a time with click-and-verify state transitions.
4. Route Base actions to the new controller.
5. Keep LT direct dictation and RT/B plain-key behavior.
6. Physically test each Base control with one-second separation and record actual UI results.

### Task 5: Route native-menu Task, System, and Developer actions

**Files:**
- Modify: `Sources/XboxCodexBridgeCore/ActionCatalog.swift`
- Modify: `Sources/XboxCodexBridge/BridgeRuntime.swift`
- Modify: `README.md`

**Steps:**

1. Add failing catalog tests for each known native item.
2. Map File actions: New Task and Open Folder.
3. Map View actions: Sidebar, Bottom Panel, Side Panel, Terminal, Browser, Previous/Next Task, Back, and Forward.
4. Map ChatGPT/Help actions: Settings, Keyboard Shortcuts, and Feedback.
5. Route Search, Add files/photos, Model picker, and mode controls through focused-window UI clicks.
6. Mark task slots, Quick Chat, Side Task, process manager, reload Skills, MCP, Git/PR, fork, and environment actions unavailable until a verified UI/native path exists.
7. Verify every mapped action returns either proven success or an explicit unavailable reason.

### Task 6: Add a guided acceptance matrix

**Files:**
- Create: `docs/ACCEPTANCE_TEST.md`
- Modify: `Sources/XboxCodexBridge/Web/index.html`
- Modify: `Sources/XboxCodexBridge/Web/app.js`

**Steps:**

1. Document every physical chord grouped by Base, Task, Developer, Safety, and System.
2. Add status columns: input seen, dispatch backend, live result, and limitation.
3. Surface backend/availability in the web mapping console.
4. Ensure dangerous/context-only actions are visibly distinguished from safe live tests.
5. Run JavaScript syntax validation.

### Task 7: Full verification and physical walkthrough

**Files:**
- Modify only if a test reveals a defect.

**Steps:**

1. Run `swift test` and require zero failures.
2. Run `xcrun swift-format lint --recursive Sources Tests Package.swift` and require no output.
3. Run `node --check Sources/XboxCodexBridge/Web/app.js`.
4. Run `swift build -c release`.
5. Restart the bridge after tests so GameController reconnects.
6. Walk every safe action physically and capture state transitions.
7. Exercise Approve/Decline only when a disposable approval prompt exists.
8. Do not execute Archive, Git/PR, upload, fork, or environment actions without an isolated disposable context and action-time approval.
9. Refresh and test `XboxCodexBridge.zip` only after the acceptance matrix is current.
