import Foundation
import XboxCodexBridgeCore

enum HapticFeedbackKind: Equatable {
  case turnStopped
  case approvalNeeded
}

struct HapticPulse: Equatable {
  let intensity: Float
  let sharpness: Float
  let relativeTime: TimeInterval
  let duration: TimeInterval
}

enum HapticPatternLibrary {
  static let manualConfirmationPulse = HapticPulse(
    intensity: 1.00,
    sharpness: 0.35,
    relativeTime: 0,
    duration: 0.40
  )

  static func pulses(for kind: HapticFeedbackKind) -> [HapticPulse] {
    switch kind {
    case .turnStopped:
      return [
        HapticPulse(intensity: 1.00, sharpness: 0.35, relativeTime: 0, duration: 0.34),
        HapticPulse(intensity: 1.00, sharpness: 0.35, relativeTime: 0.55, duration: 0.34),
      ]
    case .approvalNeeded:
      return [
        HapticPulse(intensity: 1.00, sharpness: 0.70, relativeTime: 0, duration: 0.36),
        HapticPulse(intensity: 1.00, sharpness: 0.70, relativeTime: 0.58, duration: 0.36),
        HapticPulse(intensity: 1.00, sharpness: 0.70, relativeTime: 1.16, duration: 0.36),
      ]
    }
  }
}

struct CodexApprovalControlMetadata: Equatable {
  let role: String
  let label: String
  let isEnabled: Bool
  let supportsPress: Bool
}

enum CodexApprovalControlMatcher {
  private static let supportedRoles = Set(["AXButton", "AXMenuItem"])
  private static let positiveLabels = Set([
    "allow once", "always allow", "allow this conversation", "approve",
    "允许一次", "始终允许", "允许此对话", "批准",
  ])
  private static let negativeLabels = Set([
    "deny", "decline", "reject", "拒绝",
  ])

  static func isApprovalVisible(in controls: [CodexApprovalControlMetadata]) -> Bool {
    var hasPositive = false
    var hasNegative = false
    for control in controls where isUsable(control) {
      let label = normalized(control.label)
      hasPositive = hasPositive || positiveLabels.contains(label)
      hasNegative = hasNegative || negativeLabels.contains(label)
    }
    return hasPositive && hasNegative
  }

  private static func isUsable(_ control: CodexApprovalControlMetadata) -> Bool {
    supportedRoles.contains(control.role) && control.isEnabled && control.supportsPress
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

enum CodexApprovalWindowMatcher {
  static func isApprovalVisible(in windows: [[CodexApprovalControlMetadata]]) -> Bool {
    windows.contains(where: CodexApprovalControlMatcher.isApprovalVisible)
  }
}

protocol CodexApprovalVisibilityDetecting: AnyObject {
  func isApprovalVisible() -> Bool
}

enum CodexTurnActivityMatcher {
  private static let stopLabels = Set([
    "stop", "stop generating", "stop response", "stop task", "stop-button", "stopbutton",
    "停止", "停止生成", "停止回答", "停止响应", "停止任务",
  ])

  static func isRunning(_ metadata: AccessibilityControlMetadata) -> Bool {
    guard metadata.role == "AXButton", metadata.isEnabled,
      metadata.actions.contains("AXPress")
    else { return false }

    let labels = [metadata.identifier, metadata.title, metadata.description]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    return !stopLabels.isDisjoint(with: labels)
  }
}

protocol CodexTurnActivityDetecting: AnyObject {
  func beginTrackingTurn() -> Bool
  func isTrackedTurnRunning() -> Bool
  func endTrackingTurn()
}

enum CompletionNotificationArmingPolicy {
  static func shouldArm(actionID: String) -> Bool {
    actionID == "submitWithNotification"
  }
}

final class TurnCompletionHapticCoordinator {
  typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

  private enum Phase {
    case waitingForStart
    case running(idlePolls: Int)
  }

  private let detector: CodexTurnActivityDetecting
  private let initialDelay: TimeInterval
  private let pollInterval: TimeInterval
  private let startPollLimit: Int
  private let requiredIdlePolls: Int
  private let schedule: Scheduler
  private let playHaptic: (HapticFeedbackKind) -> Void
  private let lock = NSLock()
  private var generation = 0
  private var pollCount = 0
  private var phase: Phase?

  init(
    detector: CodexTurnActivityDetecting,
    initialDelay: TimeInterval = 0.1,
    pollInterval: TimeInterval = 0.25,
    startPollLimit: Int = 20,
    requiredIdlePolls: Int = 2,
    schedule: @escaping Scheduler = { delay, operation in
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: operation)
    },
    playHaptic: @escaping (HapticFeedbackKind) -> Void
  ) {
    self.detector = detector
    self.initialDelay = initialDelay
    self.pollInterval = pollInterval
    self.startPollLimit = max(1, startPollLimit)
    self.requiredIdlePolls = max(1, requiredIdlePolls)
    self.schedule = schedule
    self.playHaptic = playHaptic
  }

  func handleSubmit() {
    lock.lock()
    generation &+= 1
    let token = generation
    let wasTracking = phase != nil
    phase = nil
    pollCount = 0
    lock.unlock()

    if wasTracking { detector.endTrackingTurn() }
    guard detector.beginTrackingTurn() else { return }

    lock.lock()
    guard generation == token else {
      lock.unlock()
      detector.endTrackingTurn()
      return
    }
    phase = .waitingForStart
    lock.unlock()
    schedulePoll(after: initialDelay, token: token)
  }

  func handleTrackedTurnEnded() {
    var shouldEnd = false
    var shouldPlay = false

    lock.lock()
    switch phase {
    case .running:
      generation &+= 1
      phase = nil
      shouldEnd = true
      shouldPlay = true
    case .waitingForStart:
      generation &+= 1
      phase = nil
      shouldEnd = true
    case nil:
      break
    }
    lock.unlock()

    if shouldEnd { detector.endTrackingTurn() }
    if shouldPlay { playHaptic(.turnStopped) }
  }

  private func schedulePoll(after delay: TimeInterval, token: Int) {
    schedule(delay) { [weak self] in
      self?.poll(token: token)
    }
  }

  private func poll(token: Int) {
    lock.lock()
    let shouldPoll = generation == token && phase != nil
    lock.unlock()
    guard shouldPoll else { return }

    let isRunning = detector.isTrackedTurnRunning()
    var shouldSchedule = false
    var shouldEnd = false
    var shouldPlay = false

    lock.lock()
    guard generation == token, let currentPhase = phase else {
      lock.unlock()
      return
    }
    pollCount += 1
    switch currentPhase {
    case .waitingForStart:
      if isRunning {
        phase = .running(idlePolls: 0)
        shouldSchedule = true
      } else if pollCount >= startPollLimit {
        phase = nil
        shouldEnd = true
      } else {
        shouldSchedule = true
      }
    case .running(let idlePolls):
      if isRunning {
        phase = .running(idlePolls: 0)
        shouldSchedule = true
      } else {
        let nextIdlePolls = idlePolls + 1
        if nextIdlePolls >= requiredIdlePolls {
          phase = nil
          shouldEnd = true
          shouldPlay = true
        } else {
          phase = .running(idlePolls: nextIdlePolls)
          shouldSchedule = true
        }
      }
    }
    lock.unlock()

    if shouldEnd { detector.endTrackingTurn() }
    if shouldPlay { playHaptic(.turnStopped) }
    if shouldSchedule { schedulePoll(after: pollInterval, token: token) }
  }
}

final class ApprovalHapticCoordinator {
  typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

  private let detector: CodexApprovalVisibilityDetecting
  private let delays: [TimeInterval]
  private let schedule: Scheduler
  private let playHaptic: (HapticFeedbackKind) -> Void
  private let lock = NSLock()
  private var isPolling = false

  init(
    detector: CodexApprovalVisibilityDetecting,
    delays: [TimeInterval] = [0.25, 0.75, 1.5, 2.5],
    schedule: @escaping Scheduler = { delay, operation in
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: operation)
    },
    playHaptic: @escaping (HapticFeedbackKind) -> Void
  ) {
    self.detector = detector
    self.delays = delays
    self.schedule = schedule
    self.playHaptic = playHaptic
  }

  func handlePermissionRequest() {
    lock.lock()
    guard !isPolling, !delays.isEmpty else {
      lock.unlock()
      return
    }
    isPolling = true
    lock.unlock()

    for (index, delay) in delays.enumerated() {
      schedule(delay) { [weak self] in
        self?.poll(isLast: index == self?.delays.indices.last)
      }
    }
  }

  private func poll(isLast: Bool) {
    lock.lock()
    let shouldPoll = isPolling
    lock.unlock()
    guard shouldPoll else { return }

    if detector.isApprovalVisible() {
      lock.lock()
      let shouldPlay = isPolling
      isPolling = false
      lock.unlock()
      if shouldPlay { playHaptic(.approvalNeeded) }
      return
    }

    if isLast {
      lock.lock()
      isPolling = false
      lock.unlock()
    }
  }
}

enum HookHapticEvent: Equatable {
  case turnStopped
  case permissionRequest
}

enum HookHapticRequestMatcher {
  private static let expectedHost = "127.0.0.1:8765"
  private static let hookHeader = "x-xbox-codex-hook"

  static func event(for request: HTTPRequest) -> HookHapticEvent? {
    guard request.method == "POST",
      request.headers["host"] == expectedHost,
      request.headers[hookHeader] == "1",
      request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true
    else { return nil }

    switch request.path {
    case "/api/hooks/turn-stopped":
      return .turnStopped
    case "/api/hooks/permission-request":
      return .permissionRequest
    default:
      return nil
    }
  }
}
