import ApplicationServices
import CoreGraphics
import XCTest
import XboxCodexBridgeCore

@testable import XboxCodexBridge

final class CodexDictationControllerTests: XCTestCase {
  func testAccessibilityBootstrapEnablesChromiumEnhancedUI() {
    var capturedAttribute = ""
    var capturedValueIsTrue = false

    let enabled = CodexAccessibilityBootstrap.enableEnhancedUserInterface {
      attribute, value in
      capturedAttribute = attribute as String
      capturedValueIsTrue = CFEqual(value, kCFBooleanTrue)
      return .success
    }

    XCTAssertTrue(enabled)
    XCTAssertEqual(capturedAttribute, "AXEnhancedUserInterface")
    XCTAssertTrue(capturedValueIsTrue)
  }

  func testAccessibilityBootstrapEnablesElectronManualAccessibility() {
    var capturedAttributes: [String] = []

    let enabled = CodexAccessibilityBootstrap.enableApplicationAccessibility {
      attribute, _ in
      capturedAttributes.append(attribute as String)
      return .success
    }

    XCTAssertTrue(enabled)
    XCTAssertEqual(
      capturedAttributes,
      ["AXManualAccessibility", "AXEnhancedUserInterface"]
    )
  }

  func testAccessibilityPressUsesAXPressWhenItReallyChangesState() {
    var events: [String] = []

    XCTAssertEqual(
      CodexAccessibilityPressPlan.perform(
        axPress: {
          events.append("ax")
          return true
        },
        verifyAfterAXPress: {
          events.append("verify-ax")
          return true
        },
        fallbackPointerClick: {
          events.append("pointer")
          return true
        },
        verifyAfterPointerClick: {
          events.append("verify-pointer")
          return true
        }
      ),
      .success
    )
    XCTAssertEqual(events, ["ax", "verify-ax"])
  }

  func testAccessibilityPressFallsBackWhenAXPressReportsFalseSuccess() {
    var events: [String] = []

    XCTAssertEqual(
      CodexAccessibilityPressPlan.perform(
        axPress: {
          events.append("ax")
          return true
        },
        verifyAfterAXPress: {
          events.append("verify-ax")
          return false
        },
        fallbackPointerClick: {
          events.append("pointer")
          return true
        },
        verifyAfterPointerClick: {
          events.append("verify-pointer")
          return true
        }
      ),
      .success
    )
    XCTAssertEqual(events, ["ax", "verify-ax", "pointer", "verify-pointer"])
  }

  func testPointerClickTargetsControlCenterAndRestoresPointer() {
    let driver = FakePointerEventDriver(currentLocation: CGPoint(x: 40, y: 50))
    let clicker = CodexPointerClicker(driver: driver)

    XCTAssertTrue(
      clicker.click(
        origin: CGPoint(x: 100, y: 200),
        size: CGSize(width: 60, height: 40)
      ))
    XCTAssertEqual(
      driver.events,
      [
        .move(CGPoint(x: 130, y: 220)),
        .down(CGPoint(x: 130, y: 220)),
        .up(CGPoint(x: 130, y: 220)),
        .move(CGPoint(x: 40, y: 50)),
      ]
    )
  }

  func testPointerHoverTargetsControlCenterWithoutClickingOrRestoring() {
    let driver = FakePointerEventDriver(currentLocation: CGPoint(x: 40, y: 50))
    let clicker = CodexPointerClicker(driver: driver)

    XCTAssertTrue(
      clicker.hover(
        origin: CGPoint(x: 100, y: 200),
        size: CGSize(width: 60, height: 40)
      ))
    XCTAssertEqual(driver.events, [.move(CGPoint(x: 130, y: 220))])
  }

  func testStartAndStopPressTheMatchingComposerControls() {
    let client = FakeCodexAccessibilityClient()
    let controller = CodexDictationController(client: client)

    let startResult = perform(.start, with: controller)
    let stopResult = perform(.stop, with: controller)

    XCTAssertTrue(startResult.accepted)
    XCTAssertTrue(stopResult.accepted)
    XCTAssertEqual(client.requestedPhases, [.start, .stop])
  }

  func testColdLaunchWaitsForDictationControlToEnterAccessibilityTree() {
    let client = FakeCodexAccessibilityClient()
    client.outcomes = [.controlNotFound, .controlNotFound, .success]
    let controller = CodexDictationController(
      client: client,
      readinessAttempts: 3,
      readinessInterval: 0,
      sleep: { _ in }
    )

    let result = perform(.start, with: controller)

    XCTAssertTrue(result.accepted)
    XCTAssertEqual(client.requestedPhases, [.start, .start, .start])
  }

  func testColdLaunchWaitsForCodexProcessBeforeLookingForDictationControl() {
    let client = FakeCodexAccessibilityClient()
    client.activateResults = [false, false, true]
    let controller = CodexDictationController(
      client: client,
      readinessAttempts: 3,
      readinessInterval: 0,
      sleep: { _ in }
    )

    let result = perform(.start, with: controller)

    XCTAssertTrue(result.accepted)
    XCTAssertEqual(client.activateCallCount, 3)
    XCTAssertEqual(client.requestedPhases, [.start])
  }

  func testMissingComposerControlReturnsActionableFailure() {
    let client = FakeCodexAccessibilityClient()
    client.outcome = .controlNotFound
    let controller = CodexDictationController(client: client, readinessAttempts: 1)

    let result = perform(.start, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(result.message, "Codex dictation button is unavailable")
  }

  func testAXPressFailureIsReported() {
    let client = FakeCodexAccessibilityClient()
    client.outcome = .pressFailed
    let controller = CodexDictationController(client: client)

    let result = perform(.stop, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(result.message, "Codex rejected the dictation button press")
  }

  func testMissingStateTransitionIsReported() {
    let client = FakeCodexAccessibilityClient()
    client.outcome = .stateUnchanged
    let controller = CodexDictationController(client: client)

    let result = perform(.start, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(result.message, "Codex did not enter dictation mode")
  }

  func testAccessibilityPermissionIsRequired() {
    let client = FakeCodexAccessibilityClient()
    client.isTrusted = false
    let controller = CodexDictationController(client: client)

    let result = perform(.start, with: controller)

    XCTAssertFalse(result.accepted)
    XCTAssertEqual(result.message, "Enable Accessibility before using dictation")
    XCTAssertTrue(client.requestedPhases.isEmpty)
  }

  func testDiagnosticsExposeTheAccessibilityClientSnapshot() {
    let client = FakeCodexAccessibilityClient()
    client.diagnosticsSnapshot = CodexDictationDiagnostics(
      accessibilityTrusted: true,
      codexIsRunning: true,
      windows: [
        CodexDictationWindowDiagnostic(
          title: "OpenAI Codex",
          role: "AXWindow",
          width: 1440,
          height: 900,
          isFocused: true,
          isMain: true
        )
      ],
      buttons: [
        CodexDictationButtonDiagnostic(
          identifier: "microphone",
          title: "Voice input",
          description: "Start voice input",
          isEnabled: true,
          supportsPress: true
        )
      ]
    )
    let controller = CodexDictationController(client: client)

    XCTAssertEqual(controller.diagnostics(), client.diagnosticsSnapshot)
  }

  private func perform(
    _ phase: CodexDictationPhase,
    with controller: CodexDictationController
  ) -> DispatchResult {
    let expectation = expectation(description: "dictation result")
    var captured: DispatchResult?
    controller.perform(phase) { result in
      captured = result
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2)
    return captured ?? DispatchResult(accepted: false, message: "missing result")
  }
}

private enum CapturedPointerEvent: Equatable {
  case move(CGPoint)
  case down(CGPoint)
  case up(CGPoint)
}

private final class FakePointerEventDriver: PointerEventDriving {
  let currentLocation: CGPoint?
  var events: [CapturedPointerEvent] = []

  init(currentLocation: CGPoint?) {
    self.currentLocation = currentLocation
  }

  func move(to point: CGPoint) -> Bool {
    events.append(.move(point))
    return true
  }

  func leftMouseDown(at point: CGPoint) -> Bool {
    events.append(.down(point))
    return true
  }

  func leftMouseUp(at point: CGPoint) -> Bool {
    events.append(.up(point))
    return true
  }
}

private final class FakeCodexAccessibilityClient: CodexAccessibilityClient {
  var isTrusted = true
  var activateResult = true
  var activateResults: [Bool] = []
  var activateCallCount = 0
  var outcome = CodexAccessibilityPressOutcome.success
  var outcomes: [CodexAccessibilityPressOutcome] = []
  var requestedPhases: [CodexDictationPhase] = []
  var diagnosticsSnapshot = CodexDictationDiagnostics(
    accessibilityTrusted: true,
    codexIsRunning: false,
    windows: [],
    buttons: []
  )

  func activateCodex() -> Bool {
    activateCallCount += 1
    return activateResults.isEmpty ? activateResult : activateResults.removeFirst()
  }

  func pressAndVerify(_ phase: CodexDictationPhase) -> CodexAccessibilityPressOutcome {
    requestedPhases.append(phase)
    return outcomes.isEmpty ? outcome : outcomes.removeFirst()
  }

  func diagnostics() -> CodexDictationDiagnostics {
    diagnosticsSnapshot
  }
}
