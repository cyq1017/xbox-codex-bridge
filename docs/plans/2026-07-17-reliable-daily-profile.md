# Reliable Daily Profile Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development and execute this plan task-by-task.

**Goal:** Replace the experimental default Xbox mapping with a reliable daily-use profile that can be used immediately and repeatedly without synthetic-shortcut false positives or analog-stick misfires.

**Architecture:** Keep every advanced action in `ActionCatalog` so it remains available for future adapters and manual remapping. Narrow `MappingConfiguration.default` to direct dictation, plain keys, verified native Codex menu actions, and verified composer accessibility controls. Analog directions are assigned only to fail-closed composer cursor and selection operations; unverified UI/shortcut actions remain unassigned. Update the dashboard to describe the reliable profile instead of claiming unsupported Micro parity.

**Tech Stack:** Swift 5.10, macOS GameController/Accessibility, local HTML/CSS/JavaScript dashboard, XCTest.

---

### Task 1: Lock the reliable mapping contract

**Files:**
- Modify: `Tests/XboxCodexBridgeCoreTests/BridgeCoreTests.swift`
- Modify: `Sources/XboxCodexBridgeCore/BridgeCore.swift`

**Step 1:** Replace the broad default-mapping assertion with exact assertions for all five layers.

**Step 2:** Add an assertion that every default action uses only `pushToTalk`, `plainKey`, or `nativeMenu` dispatch.

**Step 3:** Run `swift test --filter BridgeCoreTests/testDefaultMappingContainsReliableDailyActions` and confirm it fails against the experimental mapping.

**Step 4:** Implement the following default profile:

- Base: LT dictation, RT send, B cancel, MENU sidebar, A side panel, X bottom-panel toggle (normally the terminal), Y new task, D-pad task/panel navigation, left-stick cursor movement, right-stick selection, L3 selection/backward deletion, and R3 tap-to-focus/hold-to-clear composer gesture.
- Task (`LB`): A add selected output to task, X ask about selection in side chat, Y more details, RT new task, B cancel, D-pad left/right previous/next task, D-pad up pin/unpin.
- Developer (`RB`): A bottom panel, B terminal, X browser, Y side panel, D-pad left sidebar, D-pad down bottom panel, L3 open folder.
- Safety (`LB+RB`): A approve, B decline, D-pad up pin/unpin.
- System (`VIEW`): D-pad left/right previous/next Codex window, A settings, B keyboard shortcuts, Y feedback, MENU open folder.

Task slots, command menu, reasoning cycling, Fast, Review, command-palette actions, environment actions, Fork, and Archive remain available in the catalog but are not default mappings.

**Step 5:** Run the focused test and confirm it passes.

### Task 2: Make the dashboard honest and usable

**Files:**
- Modify: `Sources/XboxCodexBridge/Web/index.html`
- Modify: `Sources/XboxCodexBridge/Web/app.js`

**Step 1:** Change the comparison panel to a “可靠日用布局” reference with exact working controls.

**Step 2:** Fix dispatch descriptions so native menu, plain key, UI control, unavailable, and synthetic shortcut routes are shown accurately.

**Step 3:** Describe the verified analog composer-editing directions and distinguish them from unverified actions.

**Step 4:** Run `node --check Sources/XboxCodexBridge/Web/app.js`.

### Task 3: Verify and deploy the profile

**Files:**
- Review: all changed files
- Package: `XboxCodexBridge.zip`

**Step 1:** Run `swift test` and inspect the full result.

**Step 2:** Run `xcrun swift-format lint --recursive Sources Tests Package.swift`.

**Step 3:** Run `node --check Sources/XboxCodexBridge/Web/app.js`.

**Step 4:** Run `swift build -c release`.

**Step 5:** Restart the local bridge, confirm the Xbox reconnects, and physically verify LT, RT, B, MENU, A/X/Y, D-pad, `LB` task, `RB` developer, `LB+RB` safety, and `VIEW` system paths.

**Step 6:** Refresh and integrity-test the source archive.
