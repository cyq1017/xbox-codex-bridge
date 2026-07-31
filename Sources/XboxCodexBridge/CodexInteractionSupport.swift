import AppKit
import ApplicationServices
import Foundation

enum CodexAccessibilityBootstrap {
  private static let manualAccessibilityAttribute =
    "AXManualAccessibility" as CFString
  private static let enhancedUserInterfaceAttribute =
    "AXEnhancedUserInterface" as CFString

  static func enableApplicationAccessibility(
    using setAttribute: (CFString, CFTypeRef) -> AXError
  ) -> Bool {
    let manualResult = setAttribute(manualAccessibilityAttribute, kCFBooleanTrue)
    let enhancedResult = setAttribute(enhancedUserInterfaceAttribute, kCFBooleanTrue)
    return manualResult == .success || enhancedResult == .success
  }

  static func enableEnhancedUserInterface(
    using setAttribute: (CFString, CFTypeRef) -> AXError
  ) -> Bool {
    setAttribute(enhancedUserInterfaceAttribute, kCFBooleanTrue) == .success
  }

  @discardableResult
  static func enableApplicationAccessibility(for processIdentifier: pid_t) -> Bool {
    let application = AXUIElementCreateApplication(processIdentifier)
    return enableApplicationAccessibility { attribute, value in
      AXUIElementSetAttributeValue(application, attribute, value)
    }
  }
}

struct CodexWindowTitleCandidate: Equatable {
  let text: String
  let relativeX: CGFloat
  let relativeY: CGFloat
}

enum CodexWindowTitleSelector {
  static func bestTitle(in candidates: [CodexWindowTitleCandidate]) -> String? {
    candidates
      .filter { candidate in
        let title = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title.count <= 200
          && candidate.relativeX >= 0.15
          && candidate.relativeY >= 0
          && candidate.relativeY <= 0.08
      }
      .min { left, right in
        if left.relativeY == right.relativeY {
          return left.relativeX < right.relativeX
        }
        return left.relativeY < right.relativeY
      }?
      .text
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum CodexWindowCycleSelector {
  static func destinationIndex(current: Int?, count: Int, step: Int) -> Int? {
    guard count > 0 else { return nil }
    let direction = step >= 0 ? 1 : -1
    let start = current ?? (direction > 0 ? -1 : 0)
    return (start + direction + count) % count
  }
}

struct CodexWindowInfo: Codable, Equatable {
  let id: String
  let title: String
  let isFocused: Bool
}

enum OutputSelectionControl: String {
  case addToTask = "selectionAddToTask"
  case askSideChat = "selectionAskSideChat"
  case moreDetails = "selectionMoreDetails"

  var labels: [String] {
    switch self {
    case .addToTask: return ["添加到任务", "Add to task"]
    case .askSideChat: return ["在侧边聊天中提问", "Ask in side chat"]
    case .moreDetails: return ["更多详情", "More details"]
    }
  }
}

struct CodexToolbarControlMetadata: Equatable {
  let role: String
  let label: String
  let isEnabled: Bool
  let supportsPress: Bool
}

enum CodexToolbarControlSelector {
  static func bestIndex(
    in candidates: [CodexToolbarControlMetadata],
    labels: [String]
  ) -> Int? {
    candidates.indices.first { index in
      let candidate = candidates[index]
      guard candidate.isEnabled, candidate.supportsPress,
        candidate.role == kAXButtonRole as String || candidate.role == kAXMenuItemRole as String
      else { return false }
      let actual = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
      return labels.contains {
        actual.localizedCaseInsensitiveCompare($0) == .orderedSame
      }
    }
  }
}

private struct CodexWindowRecord {
  let element: AXUIElement
  let metadata: CodexWindowMetadata
  let id: String
  let taskTitle: String
}

extension SystemCodexUIActionClient {
  func focusMainWindow() -> Bool {
    guard let application = applicationElement() else { return false }
    let records = codexWindowRecords(application: application)
    guard let index = currentWindowIndex(in: records) else { return false }
    return focus(records[index], application: application)
  }

  func codexWindows() -> [CodexWindowInfo] {
    onMain {
      guard let application = applicationElement() else { return [] }
      let records = codexWindowRecords(application: application)
      let current = currentWindowIndex(in: records)
      return records.enumerated().map { index, record in
        CodexWindowInfo(id: record.id, title: record.taskTitle, isFocused: index == current)
      }
    }
  }

  func focusCodexWindow(id: String) -> Bool {
    onMain {
      guard
        let runningApplication = NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleIdentifier
        ).first,
        runningApplication.activate(options: [.activateIgnoringOtherApps]),
        let application = applicationElement(),
        let record = codexWindowRecords(application: application).first(where: { $0.id == id })
      else { return false }
      return focus(record, application: application)
    }
  }

  func codexWindowMenuEntries() -> [CodexWindowMenuEntry] {
    onMain {
      let items = codexWindowMenuItems()
      guard !items.isEmpty else { return [] }
      windowMenuTitleHistory.synchronize(windowCount: items.count)
      let currentIndex = items.firstIndex { item in
        let mark: String = attribute(kAXMenuItemMarkCharAttribute, from: item) ?? ""
        return !mark.isEmpty
      }

      if let currentIndex, let application = applicationElement() {
        let records = codexWindowRecords(application: application)
        if let recordIndex = currentWindowIndex(in: records) {
          windowMenuTitleHistory.record(records[recordIndex].taskTitle, at: currentIndex)
        }
      }

      return items.indices.map { index in
        CodexWindowMenuEntry(
          id: "window-menu-\(index)",
          title: windowMenuTitleHistory[index] ?? "Codex Window \(index + 1)",
          isCurrent: index == currentIndex
        )
      }
    }
  }

  func focusCodexWindowMenuEntry(id: String) -> Bool {
    onMain {
      guard let index = Int(id.replacingOccurrences(of: "window-menu-", with: "")),
        let runningApplication = NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleIdentifier
        ).first,
        runningApplication.activate(options: [.activateIgnoringOtherApps])
      else { return false }
      let items = codexWindowMenuItems()
      guard items.indices.contains(index) else { return false }
      return AXUIElementPerformAction(items[index], kAXPressAction as CFString) == .success
    }
  }

  func cycleCodexWindow(step: Int) -> CodexUIActionOutcome {
    let entries = codexWindowMenuEntries()
    guard
      let destination = CodexWindowCycleSelector.destinationIndex(
        current: entries.firstIndex(where: \.isCurrent),
        count: entries.count,
        step: step
      )
    else { return .targetNotFound }
    return focusCodexWindowMenuEntry(id: entries[destination].id) ? .success : .actionFailed
  }

  private func currentWindowIndex(in records: [CodexWindowRecord]) -> Int? {
    guard !records.isEmpty else { return nil }
    if let focused = records.firstIndex(where: { $0.metadata.isFocused }) {
      preferredWindowID = records[focused].id
      return focused
    }
    if let preferredWindowID,
      let preferred = records.firstIndex(where: { $0.id == preferredWindowID })
    {
      return preferred
    }
    return CodexWindowSelector.bestIndex(in: records.map(\.metadata))
  }

  private func focus(_ record: CodexWindowRecord, application: AXUIElement) -> Bool {
    let applicationFocus = AXUIElementSetAttributeValue(
      application,
      kAXFocusedWindowAttribute as CFString,
      record.element
    )
    let windowFocus = AXUIElementSetAttributeValue(
      record.element,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    let raise = AXUIElementPerformAction(record.element, kAXRaiseAction as CFString)
    let succeeded = raise == .success && (applicationFocus == .success || windowFocus == .success)
    if succeeded { preferredWindowID = record.id }
    return succeeded
  }

  private func codexWindowRecords(application: AXUIElement) -> [CodexWindowRecord] {
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: application) ?? []
    let focusedWindow: AXUIElement? = attribute(kAXFocusedWindowAttribute, from: application)
    return windows.enumerated().compactMap { index, window in
      let title: String = attribute(kAXTitleAttribute, from: window) ?? ""
      let normalizedTitle = title.lowercased()
      let size = sizeAttribute(kAXSizeAttribute, from: window) ?? .zero
      guard normalizedTitle == "chatgpt" || normalizedTitle == "codex",
        size.width > 0, size.height > 0
      else { return nil }
      let metadata = CodexWindowMetadata(
        title: title,
        size: size,
        isFocused: focusedWindow.map { CFEqual($0, window) } ?? false,
        isMain: attribute(kAXMainAttribute, from: window) ?? false
      )
      return CodexWindowRecord(
        element: window,
        metadata: metadata,
        id: String(CFHash(window), radix: 16),
        taskTitle: taskTitle(in: window) ?? "Codex Window \(index + 1)"
      )
    }
  }

  private func taskTitle(in window: AXUIElement) -> String? {
    guard let windowOrigin = pointAttribute(kAXPositionAttribute, from: window),
      let windowSize = sizeAttribute(kAXSizeAttribute, from: window),
      windowSize.width > 0, windowSize.height > 0
    else { return nil }

    let elementLimit = 1_000
    var queue = [window]
    var cursor = 0
    var candidates: [CodexWindowTitleCandidate] = []
    while cursor < queue.count && cursor < elementLimit {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if role == kAXStaticTextRole as String,
        let origin = pointAttribute(kAXPositionAttribute, from: element)
      {
        let title: String = attribute(kAXTitleAttribute, from: element) ?? ""
        let value: String = attribute(kAXValueAttribute, from: element) ?? ""
        candidates.append(
          CodexWindowTitleCandidate(
            text: title.isEmpty ? value : title,
            relativeX: (origin.x - windowOrigin.x) / windowSize.width,
            relativeY: (origin.y - windowOrigin.y) / windowSize.height
          ))
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(elementLimit - queue.count))
      }
    }
    return CodexWindowTitleSelector.bestTitle(in: candidates)
  }
}
