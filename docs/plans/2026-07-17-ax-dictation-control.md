# AX Dictation Control Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task.

**Goal:** Make LT control Codex dictation by pressing the visible composer controls through macOS Accessibility instead of synthesizing a global hotkey.

**Architecture:** Keep Xbox input, the push-to-talk state machine, and the web dashboard unchanged. Replace only the final voice-dispatch boundary with a bounded AXUIElement search that activates Codex, finds the current start/stop dictation button by stable metadata, performs AXPress, and reports a verified result. Codex must be in the foreground; no private Codex protocol or virtual HID is used.

**Tech Stack:** Swift 6, AppKit, ApplicationServices AXUIElement, XCTest, vanilla HTML/JavaScript.

---

### Task 1: Prove the Codex dictation controls are accessible

**Files:**
- Create temporarily: `work/CodexAXProbe.swift`

**Steps:**

1. Build a read-only AX probe that targets bundle identifier `com.openai.codex`.
2. Traverse only button-like elements and print role, identifier, title, description, and enabled state; do not print composer text or task content.
3. Run the probe once in idle composer state and once while dictation is active.
4. Record the stable metadata for start and stop controls. Stop implementation if neither control exposes a stable AX action.

### Task 2: Add testable button matching

**Files:**
- Create: `Sources/XboxCodexBridgeCore/DictationAccessibility.swift`
- Modify: `Tests/XboxCodexBridgeCoreTests/BridgeCoreTests.swift`

**Steps:**

1. Write failing tests for matching English and Chinese start/stop metadata and rejecting unrelated buttons.
2. Run `swift test --filter BridgeCoreTests` and verify the tests fail for the missing matcher.
3. Implement the smallest metadata model and scored matcher needed by the probe results.
4. Re-run the focused tests and verify they pass.

### Task 3: Implement the AX controller

**Files:**
- Create: `Sources/XboxCodexBridge/CodexDictationController.swift`
- Create: `Tests/XboxCodexBridgeTests/CodexDictationControllerTests.swift`

**Steps:**

1. Write failing tests against an injected accessibility-client protocol for start, stop, missing-control, and AXPress failure results.
2. Verify the focused tests fail.
3. Implement bounded traversal, foreground activation, best-candidate selection, `AXPress`, and explicit error messages.
4. Verify the controller tests pass.

### Task 4: Route LT to AX dictation

**Files:**
- Modify: `Sources/XboxCodexBridge/BridgeRuntime.swift`
- Modify: `Sources/XboxCodexBridge/CommandDispatcher.swift`
- Modify: `Sources/XboxCodexBridgeCore/ActionCatalog.swift`
- Modify: `Sources/XboxCodexBridgeCore/BridgeCore.swift`
- Modify: `Tests/XboxCodexBridgeCoreTests/BridgeCoreTests.swift`

**Steps:**

1. Write a failing test that the push-to-talk action no longer carries a synthetic key recipe.
2. Verify the test fails against the current F13 mapping.
3. Inject `CodexDictationController` into the runtime and route `.start`/`.stop` actions to AX start/stop.
4. Remove the now-unused held-key lifecycle and global-hotkey dispatch path.
5. Run all Swift tests and verify no regressions.

### Task 5: Update setup guidance and verify the real flow

**Files:**
- Modify: `Sources/XboxCodexBridge/Web/index.html`
- Modify: `Sources/XboxCodexBridge/Web/app.js`
- Modify: `README.md`

**Steps:**

1. Replace F13 setup text with the Accessibility and foreground requirement.
2. Run `node --check Sources/XboxCodexBridge/Web/app.js`.
3. Run `swift test`, `xcrun swift-format lint --recursive Sources Tests Package.swift`, and `swift build -c release`.
4. Restart the bridge and verify: LT down starts visible recording, LT up stops it, and `~/.codex/transcription-history.jsonl` gains a new entry.
5. Refresh and validate `XboxCodexBridge.zip` only after the physical end-to-end test passes.
