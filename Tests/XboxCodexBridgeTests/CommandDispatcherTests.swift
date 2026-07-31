import XCTest
import XboxCodexBridgeCore

@testable import XboxCodexBridge

final class CommandDispatcherTests: XCTestCase {
  func testLaunchCodexActivatesTheAppWithoutSendingAnAccessibilityControl() {
    let client = LaunchCodexClient()
    let dispatcher = CommandDispatcher(uiController: CodexUIActionController(client: client))
    let action = ActionDefinition(
      id: "launchCodex",
      label: "Launch Codex",
      category: "System",
      dispatch: DispatchRecipe(kind: .uiControl, uiControlID: "launchCodex")
    )
    let completed = expectation(description: "launch action completes")

    dispatcher.perform(action) { result in
      XCTAssertTrue(result.accepted)
      XCTAssertEqual(result.message, "Codex is ready.")
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
    XCTAssertEqual(client.activationCount, 1)
    XCTAssertEqual(client.performCount, 0)
  }

  func testCancelDispatchPlanSendsTwoEscapesWithAnInterval() {
    let plan = PlainKeyDispatchPlan(actionID: "cancel", key: "escape")

    XCTAssertEqual(plan.keys, ["escape", "escape"])
    XCTAssertGreaterThan(plan.interKeyDelay, 0)
  }

  func testRegularPlainKeyDispatchPlanSendsOneKey() {
    let plan = PlainKeyDispatchPlan(actionID: "submit", key: "return")

    XCTAssertEqual(plan.keys, ["return"])
    XCTAssertEqual(plan.interKeyDelay, 0)
  }

  func testModelMenuNavigationUsesKeyboardEvents() {
    XCTAssertEqual(ModelMenuKeyboardPlan.key(for: .up), "up")
    XCTAssertEqual(ModelMenuKeyboardPlan.key(for: .down), "down")
    XCTAssertEqual(ModelMenuKeyboardPlan.key(for: .enter), "right")
    XCTAssertEqual(ModelMenuKeyboardPlan.key(for: .back), "left")
    XCTAssertEqual(ModelMenuKeyboardPlan.key(for: .confirm), "return")
    XCTAssertEqual(ModelMenuKeyboardPlan.key(for: .cancel), "escape")
  }

  func testSuccessfulControllerActionsDoNotTriggerAutomaticHaptics() {
    var hapticCount = 0
    let feedback = ActionSuccessFeedback {
      hapticCount += 1
    }

    feedback.handle(
      actionID: "newTaskWindow",
      result: DispatchResult(accepted: false, message: "failed")
    )
    feedback.handle(
      actionID: "newWindow",
      result: DispatchResult(accepted: true, message: "opened")
    )
    feedback.handle(
      actionID: "newTaskWindow",
      result: DispatchResult(accepted: true, message: "ready")
    )
    feedback.handle(
      actionID: "newProjectlessTask",
      result: DispatchResult(accepted: true, message: "ready")
    )

    XCTAssertEqual(hapticCount, 0)
  }
}

private final class LaunchCodexClient: CodexUIActionClient {
  var isTrusted = true
  private(set) var activationCount = 0
  private(set) var performCount = 0

  func activateCodex() -> Bool {
    activationCount += 1
    return true
  }

  func perform(_ action: ActionDefinition) -> CodexUIActionOutcome {
    performCount += 1
    return .unsupported("The launch action must not press an accessibility control")
  }
}
