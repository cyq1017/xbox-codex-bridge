import Foundation
import XCTest
import XboxCodexBridgeCore

@testable import XboxCodexBridge

final class HapticFeedbackTests: XCTestCase {
  func testBridgeSnapshotCountsEveryCompletedTurn() {
    var snapshot = BridgeSnapshot()

    XCTAssertEqual(snapshot.completionSequence, 0)
    snapshot.recordCompletion()
    snapshot.recordCompletion()

    XCTAssertEqual(snapshot.completionSequence, 2)
  }

  func testBridgeSnapshotKeepsTheLastActionResultWhenStatusChanges() {
    var snapshot = BridgeSnapshot()

    snapshot.lastAction = "modelPicker"
    snapshot.lastActionResult = "Codex control unavailable: Open model & reasoning"
    snapshot.lastMessage = "Checking for a human approval request…"

    XCTAssertEqual(snapshot.lastAction, "modelPicker")
    XCTAssertEqual(snapshot.lastActionResult, "Codex control unavailable: Open model & reasoning")
  }

  func testBridgeSnapshotReplacesAStaleResultWithTheCurrentActionResult() {
    var snapshot = BridgeSnapshot()
    snapshot.lastActionResult = "stale result"

    snapshot.recordActionStart(id: "pushToTalk", message: "Starting dictation…")

    XCTAssertEqual(snapshot.lastAction, "pushToTalk")
    XCTAssertNil(snapshot.lastActionResult)
    XCTAssertEqual(snapshot.lastMessage, "Starting dictation…")

    snapshot.recordActionResult("Codex dictation started")

    XCTAssertEqual(snapshot.lastActionResult, "Codex dictation started")
    XCTAssertEqual(snapshot.lastMessage, "Codex dictation started")
  }

  func testManualConfirmationUsesOneMaximumStrengthLongPulse() {
    XCTAssertEqual(
      HapticPatternLibrary.manualConfirmationPulse,
      HapticPulse(intensity: 1.00, sharpness: 0.35, relativeTime: 0, duration: 0.40)
    )
  }

  func testTurnStoppedUsesTwoMaximumStrengthLongPulses() {
    XCTAssertEqual(
      HapticPatternLibrary.pulses(for: .turnStopped),
      [
        HapticPulse(intensity: 1.00, sharpness: 0.35, relativeTime: 0, duration: 0.34),
        HapticPulse(intensity: 1.00, sharpness: 0.35, relativeTime: 0.55, duration: 0.34),
      ]
    )
  }

  func testApprovalNeededUsesThreeMaximumStrengthLongPulses() {
    XCTAssertEqual(
      HapticPatternLibrary.pulses(for: .approvalNeeded),
      [
        HapticPulse(intensity: 1.00, sharpness: 0.70, relativeTime: 0, duration: 0.36),
        HapticPulse(intensity: 1.00, sharpness: 0.70, relativeTime: 0.58, duration: 0.36),
        HapticPulse(intensity: 1.00, sharpness: 0.70, relativeTime: 1.16, duration: 0.36),
      ]
    )
  }

  func testApprovalMatcherRequiresEnabledPressablePositiveAndNegativeControls() {
    let allow = approvalControl("Allow once")
    let deny = approvalControl("Deny")
    let disabledDeny = approvalControl("Deny", isEnabled: false)
    let unrelated = approvalControl("Add to task")

    XCTAssertTrue(CodexApprovalControlMatcher.isApprovalVisible(in: [allow, deny]))
    XCTAssertFalse(CodexApprovalControlMatcher.isApprovalVisible(in: [allow]))
    XCTAssertFalse(CodexApprovalControlMatcher.isApprovalVisible(in: [allow, disabledDeny]))
    XCTAssertFalse(CodexApprovalControlMatcher.isApprovalVisible(in: [allow, unrelated]))
  }

  func testApprovalMatcherSupportsExactChineseLabels() {
    XCTAssertTrue(
      CodexApprovalControlMatcher.isApprovalVisible(
        in: [approvalControl("允许一次"), approvalControl("拒绝")]
      )
    )
  }

  func testApprovalWindowMatcherFindsBackgroundWindowWithoutCombiningDifferentWindows() {
    let allow = approvalControl("Allow once")
    let deny = approvalControl("Deny")

    XCTAssertFalse(CodexApprovalWindowMatcher.isApprovalVisible(in: [[allow], [deny]]))
    XCTAssertTrue(
      CodexApprovalWindowMatcher.isApprovalVisible(
        in: [[approvalControl("Add to task")], [allow, deny]]
      )
    )
  }

  func testApprovalCoordinatorPollsUntilVisibleAndVibratesOnlyOnce() {
    let detector = StubApprovalDetector(results: [false, true, true])
    var scheduled: [() -> Void] = []
    var played: [HapticFeedbackKind] = []
    let coordinator = ApprovalHapticCoordinator(
      detector: detector,
      delays: [0.25, 0.75, 1.5],
      schedule: { _, operation in scheduled.append(operation) },
      playHaptic: { played.append($0) }
    )

    coordinator.handlePermissionRequest()
    XCTAssertEqual(scheduled.count, 3)
    scheduled.forEach { $0() }

    XCTAssertEqual(detector.callCount, 2)
    XCTAssertEqual(played, [.approvalNeeded])
  }

  func testApprovalCoordinatorDoesNotVibrateWhenApprovalUIIsNeverVisible() {
    let detector = StubApprovalDetector(results: [false, false])
    var scheduled: [() -> Void] = []
    var played: [HapticFeedbackKind] = []
    let coordinator = ApprovalHapticCoordinator(
      detector: detector,
      delays: [0.25, 0.75],
      schedule: { _, operation in scheduled.append(operation) },
      playHaptic: { played.append($0) }
    )

    coordinator.handlePermissionRequest()
    scheduled.forEach { $0() }

    XCTAssertEqual(detector.callCount, 2)
    XCTAssertTrue(played.isEmpty)
  }

  func testTurnActivityMatcherAcceptsAgentStopButRejectsDictationAndDisabledControls() {
    XCTAssertTrue(
      CodexTurnActivityMatcher.isRunning(
        control(description: "Stop")
      )
    )
    XCTAssertTrue(
      CodexTurnActivityMatcher.isRunning(
        control(description: "停止生成")
      )
    )
    XCTAssertFalse(
      CodexTurnActivityMatcher.isRunning(
        control(description: "Stop dictation")
      )
    )
    XCTAssertFalse(
      CodexTurnActivityMatcher.isRunning(
        control(description: "Stop", isEnabled: false)
      )
    )
  }

  func testCompletionNotificationArmingPolicyRequiresExplicitNotifyAction() {
    XCTAssertFalse(CompletionNotificationArmingPolicy.shouldArm(actionID: "submit"))
    XCTAssertTrue(
      CompletionNotificationArmingPolicy.shouldArm(actionID: "submitWithNotification")
    )
  }

  func testTurnCompletionCoordinatorVibratesOnceAfterRunningBecomesStablyIdle() {
    let detector = StubTurnActivityDetector(results: [false, true, true, false, false])
    var scheduled: [() -> Void] = []
    var played: [HapticFeedbackKind] = []
    let coordinator = TurnCompletionHapticCoordinator(
      detector: detector,
      initialDelay: 0.1,
      pollInterval: 0.2,
      startPollLimit: 6,
      requiredIdlePolls: 2,
      schedule: { _, operation in scheduled.append(operation) },
      playHaptic: { played.append($0) }
    )

    coordinator.handleSubmit()
    while !scheduled.isEmpty {
      scheduled.removeFirst()()
    }

    XCTAssertEqual(detector.beginCount, 1)
    XCTAssertEqual(detector.callCount, 5)
    XCTAssertEqual(detector.endCount, 1)
    XCTAssertEqual(played, [.turnStopped])
  }

  func testTurnCompletionCoordinatorVibratesForExplicitlyTrackedShortTask() {
    let detector = StubTurnActivityDetector(results: [true, false, false])
    var scheduled: [() -> Void] = []
    var played: [HapticFeedbackKind] = []
    let coordinator = TurnCompletionHapticCoordinator(
      detector: detector,
      initialDelay: 0.1,
      pollInterval: 0.2,
      startPollLimit: 6,
      requiredIdlePolls: 2,
      schedule: { _, operation in scheduled.append(operation) },
      playHaptic: { played.append($0) }
    )

    coordinator.handleSubmit()
    while !scheduled.isEmpty {
      scheduled.removeFirst()()
    }

    XCTAssertEqual(detector.endCount, 1)
    XCTAssertEqual(played, [.turnStopped])
  }

  func testExternalTurnEndDoesNothingWhenNoTaskIsTracked() {
    let detector = StubTurnActivityDetector(results: [])
    var played: [HapticFeedbackKind] = []
    let coordinator = TurnCompletionHapticCoordinator(
      detector: detector,
      schedule: { _, _ in },
      playHaptic: { played.append($0) }
    )

    coordinator.handleTrackedTurnEnded()

    XCTAssertEqual(detector.endCount, 0)
    XCTAssertTrue(played.isEmpty)
  }

  func testExternalTurnEndVibratesForExplicitlyTrackedTask() {
    let detector = StubTurnActivityDetector(results: [true])
    var scheduled: [() -> Void] = []
    var played: [HapticFeedbackKind] = []
    let coordinator = TurnCompletionHapticCoordinator(
      detector: detector,
      schedule: { _, operation in scheduled.append(operation) },
      playHaptic: { played.append($0) }
    )

    coordinator.handleSubmit()
    scheduled.removeFirst()()
    coordinator.handleTrackedTurnEnded()

    XCTAssertEqual(detector.endCount, 1)
    XCTAssertEqual(played, [.turnStopped])
  }

  func testTurnCompletionCoordinatorDoesNotVibrateWhenRunningStateNeverAppears() {
    let detector = StubTurnActivityDetector(results: [false, false, false])
    var scheduled: [() -> Void] = []
    var played: [HapticFeedbackKind] = []
    let coordinator = TurnCompletionHapticCoordinator(
      detector: detector,
      initialDelay: 0.1,
      pollInterval: 0.2,
      startPollLimit: 3,
      requiredIdlePolls: 2,
      schedule: { _, operation in scheduled.append(operation) },
      playHaptic: { played.append($0) }
    )

    coordinator.handleSubmit()
    while !scheduled.isEmpty {
      scheduled.removeFirst()()
    }

    XCTAssertEqual(detector.callCount, 3)
    XCTAssertEqual(detector.endCount, 1)
    XCTAssertTrue(played.isEmpty)
  }

  func testHookRequestMatcherAcceptsOnlyFixedLoopbackRoutesAndHeader() {
    let turnStopped = request(path: "/api/hooks/turn-stopped")
    let permission = request(path: "/api/hooks/permission-request")

    XCTAssertEqual(HookHapticRequestMatcher.event(for: turnStopped), .turnStopped)
    XCTAssertEqual(HookHapticRequestMatcher.event(for: permission), .permissionRequest)
    XCTAssertNil(
      HookHapticRequestMatcher.event(
        for: request(path: "/api/hooks/turn-stopped", hookHeader: nil)
      )
    )
    XCTAssertNil(
      HookHapticRequestMatcher.event(
        for: request(path: "/api/hooks/turn-stopped", host: "example.com")
      )
    )
    XCTAssertNil(HookHapticRequestMatcher.event(for: request(path: "/api/haptic")))
  }

  private func approvalControl(
    _ label: String,
    isEnabled: Bool = true,
    supportsPress: Bool = true
  ) -> CodexApprovalControlMetadata {
    CodexApprovalControlMetadata(
      role: "AXButton",
      label: label,
      isEnabled: isEnabled,
      supportsPress: supportsPress
    )
  }

  private func request(
    path: String,
    host: String = "127.0.0.1:8765",
    hookHeader: String? = "1"
  ) -> HTTPRequest {
    var headers = [
      "host": host,
      "content-type": "application/json",
    ]
    if let hookHeader {
      headers["x-xbox-codex-hook"] = hookHeader
    }
    let headerLines = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
    let raw = Data("POST \(path) HTTP/1.1\r\n\(headerLines)\r\nContent-Length: 2\r\n\r\n{}".utf8)
    return try! HTTPRequestParser.parse(raw)!
  }

  private func control(
    identifier: String = "",
    title: String = "",
    description: String,
    isEnabled: Bool = true,
    actions: [String] = ["AXPress"]
  ) -> AccessibilityControlMetadata {
    AccessibilityControlMetadata(
      role: "AXButton",
      identifier: identifier,
      title: title,
      description: description,
      isEnabled: isEnabled,
      actions: actions
    )
  }
}

private final class StubApprovalDetector: CodexApprovalVisibilityDetecting {
  private var results: [Bool]
  private(set) var callCount = 0

  init(results: [Bool]) {
    self.results = results
  }

  func isApprovalVisible() -> Bool {
    callCount += 1
    return results.isEmpty ? false : results.removeFirst()
  }
}

private final class StubTurnActivityDetector: CodexTurnActivityDetecting {
  private var results: [Bool]
  private(set) var beginCount = 0
  private(set) var callCount = 0
  private(set) var endCount = 0

  init(results: [Bool]) {
    self.results = results
  }

  func beginTrackingTurn() -> Bool {
    beginCount += 1
    return true
  }

  func isTrackedTurnRunning() -> Bool {
    callCount += 1
    return results.isEmpty ? false : results.removeFirst()
  }

  func endTrackingTurn() {
    endCount += 1
  }
}
