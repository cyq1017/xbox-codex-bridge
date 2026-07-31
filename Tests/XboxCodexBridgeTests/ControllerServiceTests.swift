import GameController
import XCTest

@testable import XboxCodexBridge

final class ControllerServiceTests: XCTestCase {
  func testStartEnablesBackgroundControllerEvents() {
    GCController.shouldMonitorBackgroundEvents = false
    let service = ControllerService()

    service.start()

    XCTAssertTrue(GCController.shouldMonitorBackgroundEvents)
  }

  func testSystemGesturePolicyClaimsTheViewButton() {
    let view = StubSystemGestureInput()

    ControllerSystemGesturePolicy.claim(view)

    XCTAssertEqual(view.preferredSystemGestureState, .disabled)
  }

  func testHapticLocalityPolicyUsesAllAvailableActuators() {
    XCTAssertEqual(
      ControllerHapticLocalityPolicy.preferredLocality(
        supportedLocalities: [.default, .all, .handles]
      ),
      .all
    )
  }

  func testHapticLocalityPolicyFallsBackToDefault() {
    XCTAssertEqual(
      ControllerHapticLocalityPolicy.preferredLocality(
        supportedLocalities: [.default]
      ),
      .default
    )
  }
}

private final class StubSystemGestureInput: ControllerSystemGestureInput {
  var preferredSystemGestureState: GCControllerElement.SystemGestureState = .enabled
}
