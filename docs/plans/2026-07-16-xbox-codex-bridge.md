# Xbox Codex Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a local macOS bridge that maps an Xbox controller to Codex commands and exposes a browser-based mapping and device-test console.

**Architecture:** A Swift executable uses Apple GameController for input/capability detection, CoreGraphics/Accessibility for Codex actions, and a loopback-only HTTP server for the local UI. A dependency-free HTML/CSS/JavaScript panel edits JSON mappings, visualizes live controls, compares layers with Codex Micro, and tests optional haptics/light support.

**Tech Stack:** Swift Package Manager, Swift 6 compiler in Swift 5 language mode, GameController, AppKit, ApplicationServices, CoreGraphics, POSIX loopback sockets, vanilla HTML/CSS/JavaScript, XCTest.

---

### Task 1: Core state machines

**Files:**
- Create: `Package.swift`
- Create: `Sources/XboxCodexBridgeCore/BridgeCore.swift`
- Test: `Tests/XboxCodexBridgeCoreTests/BridgeCoreTests.swift`

1. Write tests for layer precedence, stick deadzone/latching, push-to-talk hold/double-tap behavior, safety long-press, and mapping Codable round trips.
2. Run `swift test` and verify the tests fail because the core types do not exist.
3. Implement the smallest state machines and default mapping that satisfy the tests.
4. Run `swift test` and verify all core tests pass.

### Task 2: Native helper

**Files:**
- Create: `Sources/XboxCodexBridge/main.swift`
- Create: `Sources/XboxCodexBridge/BridgeRuntime.swift`
- Create: `Sources/XboxCodexBridge/ControllerService.swift`
- Create: `Sources/XboxCodexBridge/CommandDispatcher.swift`
- Create: `Sources/XboxCodexBridge/LocalHTTPServer.swift`

1. Add compilation tests through `swift build` before filling platform integration.
2. Connect controller buttons and stick thresholds to the tested core state machines.
3. Dispatch documented Codex shortcuts and reserved user-configurable shortcuts without modifying Codex.
4. Bind the server explicitly to `127.0.0.1` and require a random token for every state-changing request.
5. Expose controller, Accessibility, haptics, and light capability state.

### Task 3: Local mapping console

**Files:**
- Create: `Sources/XboxCodexBridge/Web/index.html`
- Create: `Sources/XboxCodexBridge/Web/styles.css`
- Create: `Sources/XboxCodexBridge/Web/app.js`

1. Render a CSS-built Xbox controller with clickable and live-highlighted controls.
2. Add Base, Task, Developer, Safety, and System layer tabs.
3. Add action selection, save, export/import, test-action, haptic, and light controls.
4. Show a Codex Micro comparison table and clear unsupported/deferred capability labels.
5. Verify static resources are served by the helper and the UI receives state/config JSON.

### Task 4: Handoff and verification

**Files:**
- Create: `README.md`
- Create: `run.command`

1. Document the one-time Accessibility permission and reserved Codex shortcut setup.
2. Run `swift test`, `swift build`, a release build, and a loopback HTTP smoke test.
3. Review all changed files for security, unsafe approvals, LAN exposure, error handling, and untested state transitions.
4. Fix review findings and rerun the full verification set.
