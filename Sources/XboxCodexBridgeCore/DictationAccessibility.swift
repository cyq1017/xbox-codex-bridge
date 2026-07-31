import Foundation

public enum CodexDictationPhase: Equatable, Sendable {
  case start
  case stop
}

public struct AccessibilityControlMetadata: Equatable, Sendable {
  public let role: String
  public let identifier: String
  public let title: String
  public let description: String
  public let isEnabled: Bool
  public let actions: [String]

  public init(
    role: String,
    identifier: String,
    title: String,
    description: String,
    isEnabled: Bool,
    actions: [String]
  ) {
    self.role = role
    self.identifier = identifier
    self.title = title
    self.description = description
    self.isEnabled = isEnabled
    self.actions = actions
  }
}

public enum DictationAccessibilityMatcher {
  public static func matches(
    _ metadata: AccessibilityControlMetadata,
    phase: CodexDictationPhase
  ) -> Bool {
    guard metadata.role == "AXButton", metadata.isEnabled, metadata.actions.contains("AXPress")
    else { return false }

    let labels = [metadata.identifier, metadata.title, metadata.description]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    switch phase {
    case .start:
      return !Set(labels).isDisjoint(with: ["听写", "dictation", "start dictation", "dictate"])
    case .stop:
      return !Set(labels).isDisjoint(with: ["停止听写", "stop dictation"])
    }
  }
}
