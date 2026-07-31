import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import XboxCodexBridgeCore

struct CodexWindowMetadata: Equatable {
  let title: String
  let size: CGSize
  let isFocused: Bool
  let isMain: Bool
}

enum CodexWindowSelector {
  static func bestIndex(in windows: [CodexWindowMetadata]) -> Int? {
    let candidates = windows.indices.filter { index in
      let window = windows[index]
      let title = window.title.lowercased()
      let isCodexWindow = title == "chatgpt" || title == "codex"
      return window.size.width > 0 && window.size.height > 0 && isCodexWindow
        && !title.contains("dictation") && !title.contains("听写")
    }
    if let focused = candidates.first(where: { windows[$0].isFocused }) {
      return focused
    }
    if let main = candidates.first(where: { windows[$0].isMain }) {
      return main
    }
    return candidates.max { left, right in
      area(of: windows[left]) < area(of: windows[right])
    }
  }

  private static func area(of window: CodexWindowMetadata) -> CGFloat {
    window.size.width * window.size.height
  }
}

struct CodexComposerMetadata: Equatable {
  let role: String
  let title: String
  let isEnabled: Bool
  let isFocused: Bool
  let isValueSettable: Bool
  let relativeY: CGFloat
}

enum CodexComposerSelector {
  static func bestIndex(in candidates: [CodexComposerMetadata]) -> Int? {
    let matching = candidates.indices.filter { index in
      let candidate = candidates[index]
      return candidate.role == kAXTextAreaRole as String
        && candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && candidate.isEnabled
        && candidate.isValueSettable
        && candidate.relativeY >= 0.55
        && candidate.relativeY <= 1
    }
    if let focused = matching.first(where: { candidates[$0].isFocused }) {
      return focused
    }
    return matching.max { candidates[$0].relativeY < candidates[$1].relativeY }
  }
}

enum CodexUIActionOutcome: Equatable {
  case success
  case targetNotFound
  case actionFailed
  case unsupported(String)
}

enum CodexModelPickerActivation {
  static func resolve(
    showMenuSucceeded: Bool,
    isMenuVisible: () -> Bool,
    fallbackPress: () -> CodexUIActionOutcome,
    fallbackClick: () -> CodexUIActionOutcome
  ) -> CodexUIActionOutcome {
    if showMenuSucceeded && isMenuVisible() { return .success }
    if fallbackPress() == .success && isMenuVisible() { return .success }
    return fallbackClick()
  }
}

struct CodexPermissionPickerCandidateMetadata: Equatable {
  let role: String
  let label: String
  let relativeY: Double
  let isEnabled: Bool
  let supportsPress: Bool
}

enum CodexPermissionPickerSelector {
  private static let modeLabels = Set([
    "请求批准", "替我审批", "完全访问", "完全访问权限", "自定义",
    "ask for approval", "approve for me", "full access", "custom",
  ])

  static func candidateIndices(
    in candidates: [CodexPermissionPickerCandidateMetadata]
  ) -> [Int] {
    candidates.indices.filter { index in
      let candidate = candidates[index]
      let label = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return candidate.role == kAXButtonRole as String
        && modeLabels.contains(label)
        && candidate.relativeY >= 0.75 && candidate.relativeY <= 1
        && candidate.isEnabled
        && candidate.supportsPress
    }
  }

  static func bestIndex(in candidates: [CodexPermissionPickerCandidateMetadata]) -> Int? {
    candidateIndices(in: candidates).max {
      candidates[$0].relativeY < candidates[$1].relativeY
    }
  }
}

enum CodexPermissionPickerActivation {
  static func resolve(
    pressOutcome: CodexUIActionOutcome,
    isMenuVisible: () -> Bool,
    fallbackClick: () -> CodexUIActionOutcome
  ) -> CodexUIActionOutcome {
    if pressOutcome == .success && isMenuVisible() { return .success }
    let clickOutcome = fallbackClick()
    if clickOutcome == .success && isMenuVisible() { return .success }
    if pressOutcome == .actionFailed && clickOutcome == .actionFailed { return .actionFailed }
    return .targetNotFound
  }
}

struct CodexPermissionMenuMetadata: Equatable {
  let role: String
  let label: String
  let actions: [String]
  let itemLabels: [String]
}

enum CodexPermissionMenuSelector {
  private static let modeLabels = Set([
    "请求批准", "替我审批", "完全访问", "完全访问权限", "自定义",
    "ask for approval", "approve for me", "full access", "custom",
  ])
  private static let itemPrefixes = [
    "请求批准", "替我审批", "完全访问", "自定义",
    "ask for approval", "approve for me", "full access", "custom",
  ]

  static func bestIndex(in candidates: [CodexPermissionMenuMetadata]) -> Int? {
    candidates.indices.first { index in
      let candidate = candidates[index]
      let normalizedLabel = normalized(candidate.label)
      let matchingItemCount = candidate.itemLabels.filter { label in
        let normalizedLabel = normalized(label)
        return itemPrefixes.contains { normalizedLabel.hasPrefix($0) }
      }.count
      return candidate.role == kAXMenuRole as String
        && modeLabels.contains(normalizedLabel)
        && candidate.actions.contains(kAXCancelAction as String)
        && matchingItemCount >= 3
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

struct CodexModelPickerCandidateMetadata: Codable, Equatable {
  let role: String
  let label: String
  let identifier: String
  let value: String
  let relativeX: Double
  let relativeY: Double
  let isEnabled: Bool
  let supportsShowMenu: Bool
  let supportsPress: Bool
}

enum CodexModelPickerDiagnosticsSelector {
  static func candidateIndices(in candidates: [CodexModelPickerCandidateMetadata]) -> [Int] {
    candidates.indices.filter { index in
      let candidate = candidates[index]
      return candidate.role == kAXPopUpButtonRole as String
        && candidate.relativeY >= 0.72
        && candidate.relativeY <= 1
    }
  }
}

struct CodexVisibleMenuItemMetadata: Codable, Equatable {
  let role: String
  let label: String
  let isEnabled: Bool
  let supportsPress: Bool
}

struct CodexModelOverlayElementMetadata: Codable, Equatable {
  let role: String
  let label: String
  let value: String
  let identifier: String
  let relativeX: Double
  let relativeY: Double
  let width: Double
  let height: Double
  let actions: [String]
}

enum CodexModelOverlayDiagnosticsSelector {
  static func candidateIndices(in elements: [CodexModelOverlayElementMetadata]) -> [Int] {
    let roles = Set([
      kAXButtonRole as String, kAXStaticTextRole as String,
      kAXPopUpButtonRole as String, kAXRadioButtonRole as String,
      kAXCheckBoxRole as String, kAXGroupRole as String,
      kAXListRole as String, kAXRowRole as String,
      kAXMenuItemRole as String,
    ])
    return elements.indices.filter { index in
      let element = elements[index]
      return roles.contains(element.role)
        && element.width > 0 && element.height > 0
        && element.relativeX >= -0.1 && element.relativeX <= 1.1
        && element.relativeY >= -0.1 && element.relativeY <= 1.1
        && (!element.label.isEmpty || !element.value.isEmpty || !element.actions.isEmpty)
    }
  }
}

struct CodexPopupContainerMetadata: Equatable {
  let role: String
  let actions: [String]
  let pressableMenuItemCount: Int
  let relativeY: Double
  let width: Double
  let height: Double
}

enum CodexPopupContainerSelector {
  static func bestIndex(in candidates: [CodexPopupContainerMetadata]) -> Int? {
    let customPopups = candidates.indices.filter { index in
      let candidate = candidates[index]
      return candidate.role == kAXGroupRole as String
        && candidate.actions.contains(kAXCancelAction as String)
        && candidate.pressableMenuItemCount > 0
        && candidate.relativeY >= 0.2 && candidate.relativeY <= 1
        && candidate.width > 0 && candidate.height > 0
    }
    return customPopups.min { lhs, rhs in
      candidates[lhs].width * candidates[lhs].height
        < candidates[rhs].width * candidates[rhs].height
    }
  }
}

enum CodexVisibleMenuItemSelector {
  static func candidateIndices(in items: [CodexVisibleMenuItemMetadata]) -> [Int] {
    items.indices.filter { index in
      let item = items[index]
      return [kAXMenuItemRole as String, kAXButtonRole as String].contains(item.role)
        && item.isEnabled
        && item.supportsPress
        && !item.label.isEmpty
    }
  }
}

enum CodexModelMenuSelection {
  static func destinationIndex(current: Int?, count: Int, step: Int) -> Int? {
    guard count > 0 else { return nil }
    guard let current else { return step < 0 ? count - 1 : 0 }
    return min(max(current + step, 0), count - 1)
  }
}

enum CodexModelMenuItemActivationRoute: Equatable {
  case pointerClick
}

enum CodexModelMenuItemActivation {
  static let preferredRoute: CodexModelMenuItemActivationRoute = .pointerClick
}

enum CodexPermissionMenuItemActivation {
  static let preferredRoute: CodexModelMenuItemActivationRoute = .pointerClick
}

enum CodexPermissionMenuCancellation {
  static func resolve(
    menuIsStillVisible: Bool,
    fallbackEscape: () -> Bool
  ) -> CodexUIActionOutcome {
    guard menuIsStillVisible else { return .success }
    return fallbackEscape() ? .success : .actionFailed
  }
}

protocol CodexUIActionClient: AnyObject {
  var isTrusted: Bool { get }

  func activateCodex() -> Bool
  func perform(_ action: ActionDefinition) -> CodexUIActionOutcome
}

protocol CodexWindowClient: AnyObject {
  func codexWindows() -> [CodexWindowInfo]
  func focusCodexWindow(id: String) -> Bool
}

struct CodexWindowMenuEntry: Equatable {
  let id: String
  let title: String
  let isCurrent: Bool
}

protocol CodexGlobalWindowClient: AnyObject {
  func codexWindowMenuEntries() -> [CodexWindowMenuEntry]
  func focusCodexWindowMenuEntry(id: String) -> Bool
}

protocol CodexModelPickerDiagnosticsClient: AnyObject {
  func modelPickerCandidates() -> [CodexModelPickerCandidateMetadata]
}

protocol CodexModelMenuDiagnosticsClient: AnyObject {
  func visibleModelMenuItems() -> [CodexVisibleMenuItemMetadata]
}

protocol CodexModelOverlayDiagnosticsClient: AnyObject {
  func visibleModelOverlayElements() -> [CodexModelOverlayElementMetadata]
}

protocol CodexModelMenuNavigationClient: AnyObject {
  func performModelMenuNavigation(
    _ navigation: ModelMenuNavigationAction
  ) -> CodexUIActionOutcome
}

protocol CodexPermissionMenuNavigationClient: AnyObject {
  func performPermissionMenuNavigation(
    _ navigation: ModelMenuNavigationAction
  ) -> CodexUIActionOutcome
}

protocol CodexPermissionMenuVisibilityClient: AnyObject {
  func isPermissionMenuVisible() -> Bool
}

final class CodexUIActionController {
  private let client: CodexUIActionClient
  private let queue = DispatchQueue(label: "XboxCodexBridge.CodexUIActionController")
  private let readinessAttempts: Int
  private let readinessInterval: TimeInterval
  private let sleep: (TimeInterval) -> Void

  init(
    client: CodexUIActionClient,
    readinessAttempts: Int = 80,
    readinessInterval: TimeInterval = 0.1,
    sleep: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
  ) {
    self.client = client
    self.readinessAttempts = max(1, readinessAttempts)
    self.readinessInterval = max(0, readinessInterval)
    self.sleep = sleep
  }

  var isAccessibilityTrusted: Bool {
    client.isTrusted
  }

  func activateCodex() -> Bool {
    client.activateCodex()
  }

  func codexWindows() -> [CodexWindowInfo] {
    guard client.isTrusted else { return [] }
    return (client as? CodexWindowClient)?.codexWindows() ?? []
  }

  func focusCodexWindow(id: String) -> Bool {
    guard client.isTrusted else { return false }
    return (client as? CodexWindowClient)?.focusCodexWindow(id: id) ?? false
  }

  func codexWindowMenuEntries() -> [CodexWindowMenuEntry] {
    guard client.isTrusted else { return [] }
    return (client as? CodexGlobalWindowClient)?.codexWindowMenuEntries() ?? []
  }

  func focusCodexWindowMenuEntry(id: String) -> Bool {
    guard client.isTrusted else { return false }
    return (client as? CodexGlobalWindowClient)?.focusCodexWindowMenuEntry(id: id) ?? false
  }

  func modelPickerCandidates() -> [CodexModelPickerCandidateMetadata] {
    guard client.isTrusted else { return [] }
    return (client as? CodexModelPickerDiagnosticsClient)?.modelPickerCandidates() ?? []
  }

  func visibleModelMenuItems() -> [CodexVisibleMenuItemMetadata] {
    guard client.isTrusted else { return [] }
    return (client as? CodexModelMenuDiagnosticsClient)?.visibleModelMenuItems() ?? []
  }

  func visibleModelOverlayElements() -> [CodexModelOverlayElementMetadata] {
    guard client.isTrusted else { return [] }
    return (client as? CodexModelOverlayDiagnosticsClient)?.visibleModelOverlayElements() ?? []
  }

  func isPermissionMenuVisible() -> Bool {
    guard client.isTrusted else { return false }
    return (client as? CodexPermissionMenuVisibilityClient)?.isPermissionMenuVisible() ?? false
  }

  func performModelMenuNavigation(
    _ navigation: ModelMenuNavigationAction,
    completion: @escaping (DispatchResult) -> Void
  ) {
    guard client.isTrusted else {
      completion(
        DispatchResult(
          accepted: false,
          message: "Enable Accessibility for the bridge before navigating the model menu"
        ))
      return
    }
    guard let navigationClient = client as? CodexModelMenuNavigationClient else {
      completion(
        DispatchResult(
          accepted: false,
          message: "Direct model-menu navigation is unavailable"
        ))
      return
    }

    queue.async {
      let outcome = navigationClient.performModelMenuNavigation(navigation)
      let accepted = outcome == .success
      let message: String
      switch outcome {
      case .success:
        message = "Controlled the visible model menu."
      case .targetNotFound:
        message = "The model menu is no longer visible."
      case .actionFailed:
        message = "Codex rejected direct model-menu navigation."
      case .unsupported(let reason):
        message = reason
      }
      completion(DispatchResult(accepted: accepted, message: message))
    }
  }

  func performPermissionMenuNavigation(
    _ navigation: ModelMenuNavigationAction,
    completion: @escaping (DispatchResult) -> Void
  ) {
    guard client.isTrusted else {
      completion(
        DispatchResult(
          accepted: false,
          message: "Enable Accessibility for the bridge before navigating the permission menu"
        ))
      return
    }
    guard let navigationClient = client as? CodexPermissionMenuNavigationClient else {
      completion(
        DispatchResult(
          accepted: false,
          message: "Direct permission-menu navigation is unavailable"
        ))
      return
    }

    queue.async {
      let outcome = navigationClient.performPermissionMenuNavigation(navigation)
      let accepted = outcome == .success
      let message: String
      switch outcome {
      case .success:
        message = "Controlled the visible permission menu."
      case .targetNotFound:
        message = "The permission menu is no longer visible."
      case .actionFailed:
        message = "Codex rejected direct permission-menu navigation."
      case .unsupported(let reason):
        message = reason
      }
      completion(DispatchResult(accepted: accepted, message: message))
    }
  }

  func requestAccessibilityIfNeeded() {
    guard !client.isTrusted else { return }
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  func perform(
    _ action: ActionDefinition,
    completion: @escaping (DispatchResult) -> Void
  ) {
    if action.dispatch.kind == .unavailable {
      completion(
        DispatchResult(
          accepted: false,
          message: action.dispatch.unavailableReason ?? "Action is unavailable"
        ))
      return
    }
    guard client.isTrusted else {
      completion(
        DispatchResult(
          accepted: false,
          message: "Enable Accessibility for the bridge before sending Codex commands"
        ))
      return
    }

    queue.async { [client, readinessAttempts, readinessInterval, sleep] in
      var activated = false
      for attempt in 0..<readinessAttempts {
        if client.activateCodex() {
          activated = true
          break
        }
        if attempt < readinessAttempts - 1 { sleep(readinessInterval) }
      }
      guard activated else {
        completion(DispatchResult(accepted: false, message: "Codex App is not installed"))
        return
      }
      Thread.sleep(forTimeInterval: 0.12)

      var outcome: CodexUIActionOutcome
      if action.dispatch.uiControlID == "newTaskWindow" {
        outcome = Self.performNewTaskWindow(using: client)
      } else {
        outcome = .targetNotFound
        for attempt in 0..<readinessAttempts {
          outcome = client.perform(action)
          if outcome != .targetNotFound { break }
          if attempt < readinessAttempts - 1 { sleep(readinessInterval) }
        }
      }
      completion(Self.result(for: action, outcome: outcome))
    }
  }

  private static func performNewTaskWindow(
    using client: CodexUIActionClient
  ) -> CodexUIActionOutcome {
    guard let windowClient = client as? CodexWindowClient else {
      return .unsupported("Codex window discovery is unavailable")
    }
    guard let newWindow = ActionCatalog.definition(for: "newWindow"),
      let newTask = ActionCatalog.definition(for: "newTask"),
      let focusComposer = ActionCatalog.definition(for: "focusComposer")
    else { return .unsupported("Task-window workflow actions are missing") }

    let existingWindowIDs = Set(windowClient.codexWindows().map(\.id))
    let windowOutcome = client.perform(newWindow)
    guard windowOutcome == .success else { return windowOutcome }

    guard
      let newWindowID = waitForNewWindow(
        using: windowClient,
        excluding: existingWindowIDs
      )
    else { return .actionFailed }
    guard windowClient.focusCodexWindow(id: newWindowID) else { return .actionFailed }
    guard waitUntilWindowFocused(using: windowClient, id: newWindowID) else {
      return .actionFailed
    }

    let taskOutcome = client.perform(newTask)
    guard taskOutcome == .success else { return taskOutcome }
    return waitForComposer(using: client, action: focusComposer)
  }

  private static func waitForNewWindow(
    using client: CodexWindowClient,
    excluding existingWindowIDs: Set<String>
  ) -> String? {
    for attempt in 0..<20 {
      let newWindows = client.codexWindows().filter { !existingWindowIDs.contains($0.id) }
      if let window = newWindows.first(where: \.isFocused) ?? newWindows.first {
        return window.id
      }
      if attempt < 19 { Thread.sleep(forTimeInterval: 0.05) }
    }
    return nil
  }

  private static func waitUntilWindowFocused(
    using client: CodexWindowClient,
    id: String
  ) -> Bool {
    for attempt in 0..<20 {
      if client.codexWindows().contains(where: { $0.id == id && $0.isFocused }) {
        return true
      }
      if attempt < 19 { Thread.sleep(forTimeInterval: 0.05) }
    }
    return false
  }

  private static func waitForComposer(
    using client: CodexUIActionClient,
    action: ActionDefinition
  ) -> CodexUIActionOutcome {
    var outcome = CodexUIActionOutcome.targetNotFound
    for attempt in 0..<20 {
      outcome = client.perform(action)
      if outcome == .success { return .success }
      if outcome != .targetNotFound { return outcome }
      if attempt < 19 { Thread.sleep(forTimeInterval: 0.05) }
    }
    return outcome
  }

  private static func result(
    for action: ActionDefinition,
    outcome: CodexUIActionOutcome
  ) -> DispatchResult {
    switch outcome {
    case .success:
      return DispatchResult(accepted: true, message: "Opened \(action.label).")
    case .targetNotFound:
      return DispatchResult(
        accepted: false,
        message: "Codex control unavailable: \(action.label)"
      )
    case .actionFailed:
      return DispatchResult(accepted: false, message: "Codex rejected \(action.label)")
    case .unsupported(let reason):
      return DispatchResult(
        accepted: false,
        message: "Unsupported Codex UI route for \(action.label): \(reason)"
      )
    }
  }
}

final class SystemCodexUIActionClient: CodexUIActionClient, CodexWindowClient,
  CodexGlobalWindowClient, CodexApprovalVisibilityDetecting, CodexTurnActivityDetecting,
  CodexModelPickerDiagnosticsClient,
  CodexModelMenuDiagnosticsClient, CodexModelMenuNavigationClient,
  CodexModelOverlayDiagnosticsClient, CodexPermissionMenuNavigationClient,
  CodexPermissionMenuVisibilityClient
{
  let bundleIdentifier = "com.openai.codex"
  let maximumElementCount = 10_000
  private let clicker: CodexPointerClicker
  var preferredWindowID: String?
  var windowMenuTitleHistory = CodexWindowTitleHistory()
  private var modelMenuSelectionIndex: Int?
  private var permissionMenuSelectionIndex: Int?
  private var trackedTurnWindow: AXUIElement?

  init(clicker: CodexPointerClicker = CodexPointerClicker(driver: SystemPointerEventDriver())) {
    self.clicker = clicker
  }

  var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  func activateCodex() -> Bool {
    let opened = onMain {
      if let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).first {
        CodexAccessibilityBootstrap.enableApplicationAccessibility(
          for: application.processIdentifier
        )
        return application.activate(options: [.activateIgnoringOtherApps])
      }
      guard
        let url = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: bundleIdentifier
        )
      else {
        return false
      }
      return NSWorkspace.shared.open(url)
    }
    guard opened else { return false }
    return onMain {
      guard
        let application = NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleIdentifier
        ).first,
        application.activate(options: [.activateIgnoringOtherApps])
      else { return false }
      CodexAccessibilityBootstrap.enableApplicationAccessibility(
        for: application.processIdentifier
      )
      _ = focusMainWindow()
      return true
    }
  }

  func perform(_ action: ActionDefinition) -> CodexUIActionOutcome {
    onMain {
      switch action.dispatch.kind {
      case .nativeMenu:
        guard let path = action.dispatch.menuPath else {
          return .unsupported("Native menu path is missing")
        }
        return pressNativeMenu(path)
      case .uiControl:
        guard let controlID = action.dispatch.uiControlID else {
          return .unsupported("UI control identifier is missing")
        }
        return pressUIControl(controlID)
      case .commandPalette, .shortcut, .keystroke:
        return .unsupported("Synthetic shortcut dispatch is disabled")
      case .plainKey:
        return .unsupported("Plain key dispatch belongs to the keyboard input path")
      case .pushToTalk:
        return .unsupported("Push to talk uses the direct dictation path")
      case .unavailable:
        return .unsupported("No verified Codex UI adapter is configured")
      }
    }
  }

  func isApprovalVisible() -> Bool {
    guard isTrusted else { return false }
    return onMain {
      guard let application = applicationElement() else { return false }
      var windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: application) ?? []
      if windows.isEmpty,
        let focused: AXUIElement = attribute(kAXFocusedWindowAttribute, from: application)
      {
        windows = [focused]
      }
      return CodexApprovalWindowMatcher.isApprovalVisible(
        in: windows.map(approvalControls(in:))
      )
    }
  }

  func beginTrackingTurn() -> Bool {
    guard isTrusted else { return false }
    return onMain {
      trackedTurnWindow = targetWindow()
      return trackedTurnWindow != nil
    }
  }

  func isTrackedTurnRunning() -> Bool {
    guard isTrusted else { return false }
    return onMain {
      guard let trackedTurnWindow else { return false }
      return turnControls(in: trackedTurnWindow).contains(where: CodexTurnActivityMatcher.isRunning)
    }
  }

  func endTrackingTurn() {
    onMain { trackedTurnWindow = nil }
  }

  func modelPickerCandidates() -> [CodexModelPickerCandidateMetadata] {
    guard isTrusted else { return [] }
    return onMain { self.collectModelPickerCandidates() }
  }

  func visibleModelMenuItems() -> [CodexVisibleMenuItemMetadata] {
    guard isTrusted else { return [] }
    return onMain { self.collectVisibleModelMenuItems() }
  }

  func visibleModelOverlayElements() -> [CodexModelOverlayElementMetadata] {
    guard isTrusted else { return [] }
    return onMain { self.collectVisibleModelOverlayElements() }
  }

  func performModelMenuNavigation(
    _ navigation: ModelMenuNavigationAction
  ) -> CodexUIActionOutcome {
    guard isTrusted else { return .actionFailed }
    return onMain { self.navigateVisibleModelMenu(navigation) }
  }

  func performPermissionMenuNavigation(
    _ navigation: ModelMenuNavigationAction
  ) -> CodexUIActionOutcome {
    guard isTrusted else { return .actionFailed }
    return onMain { self.navigateVisiblePermissionMenu(navigation) }
  }

  func isPermissionMenuVisible() -> Bool {
    guard isTrusted else { return false }
    return onMain { self.visiblePermissionMenu() != nil }
  }

  private func approvalControls(in root: AXUIElement) -> [CodexApprovalControlMetadata] {
    var queue = [root]
    var cursor = 0
    var controls: [CodexApprovalControlMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if role == kAXButtonRole as String || role == kAXMenuItemRole as String {
        controls.append(
          CodexApprovalControlMetadata(
            role: role,
            label: elementLabel(element),
            isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
            supportsPress: actionNames(of: element).contains(kAXPressAction as String)
          ))
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return controls
  }

  private func turnControls(in root: AXUIElement) -> [AccessibilityControlMetadata] {
    var queue = [root]
    var cursor = 0
    var controls: [AccessibilityControlMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if role == kAXButtonRole as String {
        controls.append(
          AccessibilityControlMetadata(
            role: role,
            identifier: attribute(kAXIdentifierAttribute, from: element) ?? "",
            title: attribute(kAXTitleAttribute, from: element) ?? "",
            description: attribute(kAXDescriptionAttribute, from: element) ?? "",
            isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
            actions: actionNames(of: element)
          ))
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return controls
  }

  private func pressNativeMenu(_ path: [String]) -> CodexUIActionOutcome {
    guard let item = findMenuItem(path: path) else { return .targetNotFound }
    let error = AXUIElementPerformAction(item, kAXPressAction as CFString)
    return error == .success ? .success : .actionFailed
  }

  private func pressUIControl(_ controlID: String) -> CodexUIActionOutcome {
    if let command = ComposerEditCommand(rawValue: controlID) {
      return editComposer(command)
    }
    if let control = OutputSelectionControl(rawValue: controlID) {
      return pressOutputSelectionControl(control)
    }
    switch controlID {
    case "focusComposer":
      return focusComposer()
    case "clearComposer":
      return clearComposer()
    case "previousWindow":
      return cycleCodexWindow(step: -1)
    case "nextWindow":
      return cycleCodexWindow(step: 1)
    case "modelPicker":
      return showModelPicker()
    case "permissionPicker":
      return showPermissionPicker()
    case "addFiles":
      return clickControl(
        descriptions: ["添加文件等内容", "Add files"],
        titles: ["添加文件等内容", "Add files"],
        roles: [kAXButtonRole]
      )
    case "addPhotos":
      let addFiles = clickControl(
        descriptions: ["添加文件等内容", "Add files"],
        titles: ["添加文件等内容", "Add files"],
        roles: [kAXButtonRole]
      )
      guard addFiles == .success else { return addFiles }
      Thread.sleep(forTimeInterval: 0.1)
      return clickMenuItem(containing: ["照片", "photo", "image", "图片"])
    case "searchTasks":
      return clickControl(
        descriptions: ["搜索", "Search"],
        titles: ["搜索", "Search"],
        roles: [kAXButtonRole, kAXTextFieldRole]
      )
    case "reasoningIncrease", "reasoningDecrease", "reasoningCycle":
      return performReasoningControl(controlID)
    case "fastToggle":
      return clickControl(
        descriptions: ["Fast", "快速"],
        titles: ["Fast", "快速"],
        roles: [kAXButtonRole, kAXMenuItemRole]
      )
    case "planToggle":
      return clickControl(
        descriptions: ["Plan", "计划"],
        titles: ["Plan", "计划"],
        roles: [kAXButtonRole, kAXMenuItemRole]
      )
    case "review":
      return clickControl(
        descriptions: ["Review", "审查"],
        titles: ["Review", "审查"],
        roles: [kAXButtonRole, kAXMenuItemRole]
      )
    case "commandMenu":
      return .unsupported("No stable command-menu control was found")
    default:
      return .unsupported("No stable control mapping exists")
    }
  }

  private func pressOutputSelectionControl(
    _ control: OutputSelectionControl
  ) -> CodexUIActionOutcome {
    guard let element = findExactToolbarControl(labels: control.labels) else {
      return .targetNotFound
    }
    let press = AXUIElementPerformAction(element, kAXPressAction as CFString)
    return press == .success ? .success : click(element)
  }

  private func findExactToolbarControl(labels: [String]) -> AXUIElement? {
    guard let root = targetWindow() else { return nil }
    do {
      var queue = [root]
      var cursor = 0
      var elements: [AXUIElement] = []
      var metadata: [CodexToolbarControlMetadata] = []
      while cursor < queue.count && cursor < maximumElementCount {
        let element = queue[cursor]
        cursor += 1
        let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
        if role == kAXButtonRole as String || role == kAXMenuItemRole as String {
          elements.append(element)
          metadata.append(
            CodexToolbarControlMetadata(
              role: role,
              label: elementLabel(element),
              isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
              supportsPress: actionNames(of: element).contains(kAXPressAction as String)
            ))
        }
        if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
          queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
        }
      }
      if let index = CodexToolbarControlSelector.bestIndex(in: metadata, labels: labels) {
        return elements[index]
      }
    }
    return nil
  }

  private func focusComposer() -> CodexUIActionOutcome {
    guard let composer = findComposer() else { return .targetNotFound }
    let focus = AXUIElementSetAttributeValue(
      composer,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    if focus == .success { return .success }
    return click(composer)
  }

  private func clearComposer() -> CodexUIActionOutcome {
    guard let composer = findComposer() else { return .targetNotFound }
    let error = AXUIElementSetAttributeValue(
      composer,
      kAXValueAttribute as CFString,
      "" as CFString
    )
    return error == .success ? .success : .actionFailed
  }

  private func editComposer(_ command: ComposerEditCommand) -> CodexUIActionOutcome {
    guard let composer = findComposer(),
      isAttributeSettable(kAXSelectedTextRangeAttribute, on: composer),
      let text: String = attribute(kAXValueAttribute, from: composer),
      let selection = rangeAttribute(kAXSelectedTextRangeAttribute, from: composer)
    else { return .targetNotFound }

    let edited = ComposerTextEditor.apply(
      command,
      to: ComposerTextState(text: text, selection: selection)
    )
    if edited.text != text {
      let valueResult = AXUIElementSetAttributeValue(
        composer,
        kAXValueAttribute as CFString,
        edited.text as CFString
      )
      guard valueResult == .success else { return .actionFailed }
    }
    guard let rangeValue = axRangeValue(edited.selection) else { return .actionFailed }
    let selectionResult = AXUIElementSetAttributeValue(
      composer,
      kAXSelectedTextRangeAttribute as CFString,
      rangeValue
    )
    guard selectionResult == .success else { return .actionFailed }
    _ = AXUIElementSetAttributeValue(
      composer,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    return .success
  }

  private func findComposer() -> AXUIElement? {
    guard let window = targetWindow(),
      let windowOrigin = pointAttribute(kAXPositionAttribute, from: window),
      let windowSize = sizeAttribute(kAXSizeAttribute, from: window),
      windowSize.height > 0
    else { return nil }

    var queue = [window]
    var cursor = 0
    var elements: [AXUIElement] = []
    var metadata: [CodexComposerMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if role == kAXTextAreaRole as String,
        let origin = pointAttribute(kAXPositionAttribute, from: element)
      {
        elements.append(element)
        metadata.append(
          CodexComposerMetadata(
            role: role,
            title: attribute(kAXTitleAttribute, from: element) ?? "",
            isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
            isFocused: attribute(kAXFocusedAttribute, from: element) ?? false,
            isValueSettable: isAttributeSettable(kAXValueAttribute, on: element),
            relativeY: (origin.y - windowOrigin.y) / windowSize.height
          ))
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    guard let index = CodexComposerSelector.bestIndex(in: metadata) else { return nil }
    return elements[index]
  }

  private func performReasoningControl(_ controlID: String) -> CodexUIActionOutcome {
    let picker = showModelPicker()
    guard picker == .success else { return picker }
    Thread.sleep(forTimeInterval: 0.1)

    let labels: [[String]]
    switch controlID {
    case "reasoningIncrease":
      labels = [["high", "高", "极高", "very high"]]
    case "reasoningDecrease":
      labels = [["low", "低", "中", "medium"]]
    default:
      labels = [["reasoning", "推理", "low", "medium", "high", "高"]]
    }
    return clickMenuItem(containing: labels.flatMap { $0 })
  }

  private func showModelPicker() -> CodexUIActionOutcome {
    modelMenuSelectionIndex = nil
    guard let element = findModelPicker() else { return .targetNotFound }
    let error = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
    if error == .success { Thread.sleep(forTimeInterval: 0.08) }
    return CodexModelPickerActivation.resolve(
      showMenuSucceeded: error == .success,
      isMenuVisible: isPopupMenuVisible,
      fallbackPress: {
        let outcome = press(element)
        if outcome == .success { Thread.sleep(forTimeInterval: 0.08) }
        return outcome
      },
      fallbackClick: { click(element) }
    )
  }

  private func showPermissionPicker() -> CodexUIActionOutcome {
    permissionMenuSelectionIndex = nil
    guard let element = findPermissionPicker() else { return .targetNotFound }

    let pressOutcome = press(element)
    if pressOutcome == .success { Thread.sleep(forTimeInterval: 0.08) }
    return CodexPermissionPickerActivation.resolve(
      pressOutcome: pressOutcome,
      isMenuVisible: { self.visiblePermissionMenu() != nil },
      fallbackClick: {
        let outcome = self.click(element)
        if outcome == .success { Thread.sleep(forTimeInterval: 0.08) }
        return outcome
      }
    )
  }

  private func findPermissionPicker() -> AXUIElement? {
    guard let window = targetWindow(),
      let windowOrigin = pointAttribute(kAXPositionAttribute, from: window),
      let windowSize = sizeAttribute(kAXSizeAttribute, from: window),
      windowSize.height > 0
    else { return nil }

    var queue = [window]
    var cursor = 0
    var elements: [AXUIElement] = []
    var metadata: [CodexPermissionPickerCandidateMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if role == kAXButtonRole as String,
        let origin = pointAttribute(kAXPositionAttribute, from: element)
      {
        let actions = actionNames(of: element)
        elements.append(element)
        metadata.append(
          CodexPermissionPickerCandidateMetadata(
            role: role,
            label: elementLabel(element),
            relativeY: Double((origin.y - windowOrigin.y) / windowSize.height),
            isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
            supportsPress: actions.contains(kAXPressAction as String)
          ))
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    guard let index = CodexPermissionPickerSelector.bestIndex(in: metadata) else { return nil }
    return elements[index]
  }

  private func visiblePermissionMenu() -> AXUIElement? {
    guard let application = applicationElement() else { return nil }
    var queue = [application]
    var cursor = 0
    var elements: [AXUIElement] = []
    var metadata: [CodexPermissionMenuMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
      if role == kAXMenuRole as String {
        elements.append(element)
        metadata.append(
          CodexPermissionMenuMetadata(
            role: role,
            label: elementLabel(element),
            actions: actionNames(of: element),
            itemLabels: permissionMenuItemElements(in: element).map(elementLabel)
          ))
      }
      queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
    }
    guard let index = CodexPermissionMenuSelector.bestIndex(in: metadata) else { return nil }
    return elements[index]
  }

  private func isPopupMenuVisible() -> Bool {
    visiblePopupMenu() != nil
  }

  private func visiblePopupMenu() -> AXUIElement? {
    guard let application = applicationElement(),
      let window = targetWindow(),
      let windowOrigin = pointAttribute(kAXPositionAttribute, from: window),
      let windowSize = sizeAttribute(kAXSizeAttribute, from: window),
      windowSize.height > 0
    else { return nil }
    var queue = [application]
    var cursor = 0
    var candidates: [(element: AXUIElement, metadata: CodexPopupContainerMetadata)] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
      let actions = actionNames(of: element)
      if (role == kAXMenuRole as String
        || (role == kAXGroupRole as String && actions.contains(kAXCancelAction as String))),
        let origin = pointAttribute(kAXPositionAttribute, from: element),
        let size = sizeAttribute(kAXSizeAttribute, from: element),
        origin.y > windowOrigin.y + 10,
        size.width > 0,
        size.height > 0,
        !children.isEmpty
      {
        candidates.append(
          (
            element,
            CodexPopupContainerMetadata(
              role: role,
              actions: actions,
              pressableMenuItemCount: pressableMenuItemCount(in: element),
              relativeY: (origin.y - windowOrigin.y) / windowSize.height,
              width: size.width,
              height: size.height
            )
          ))
      }
      queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
    }
    guard
      let index = CodexPopupContainerSelector.bestIndex(
        in: candidates.map(\.metadata)
      )
    else { return nil }
    return candidates[index].element
  }

  private func pressableMenuItemCount(in root: AXUIElement) -> Int {
    var queue = [root]
    var cursor = 0
    var count = 0
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      let isEnabled: Bool = attribute(kAXEnabledAttribute, from: element) ?? false
      if role == kAXMenuItemRole as String, isEnabled,
        actionNames(of: element).contains(kAXPressAction as String)
      {
        count += 1
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return count
  }

  private func findModelPicker() -> AXUIElement? {
    guard let window = targetWindow(),
      let windowOrigin = pointAttribute(kAXPositionAttribute, from: window),
      let windowSize = sizeAttribute(kAXSizeAttribute, from: window)
    else { return nil }

    let lowerBoundary = windowOrigin.y + windowSize.height * 0.72
    var queue = [window]
    var cursor = 0
    var candidates: [(AXUIElement, CGPoint)] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if role == kAXPopUpButtonRole as String,
        let origin = pointAttribute(kAXPositionAttribute, from: element),
        origin.y >= lowerBoundary
      {
        candidates.append((element, origin))
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return candidates.max { $0.1.x < $1.1.x }?.0
  }

  private func collectModelPickerCandidates() -> [CodexModelPickerCandidateMetadata] {
    guard let window = targetWindow(),
      let windowOrigin = pointAttribute(kAXPositionAttribute, from: window),
      let windowSize = sizeAttribute(kAXSizeAttribute, from: window),
      windowSize.width > 0,
      windowSize.height > 0
    else { return [] }

    var queue = [window]
    var cursor = 0
    var candidates: [CodexModelPickerCandidateMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if let origin = pointAttribute(kAXPositionAttribute, from: element) {
        let actions = actionNames(of: element)
        candidates.append(
          CodexModelPickerCandidateMetadata(
            role: role,
            label: elementLabel(element),
            identifier: attribute(kAXIdentifierAttribute, from: element) ?? "",
            value: attribute(kAXValueAttribute, from: element) ?? "",
            relativeX: Double((origin.x - windowOrigin.x) / windowSize.width),
            relativeY: Double((origin.y - windowOrigin.y) / windowSize.height),
            isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
            supportsShowMenu: actions.contains(kAXShowMenuAction as String),
            supportsPress: actions.contains(kAXPressAction as String)
          )
        )
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return CodexModelPickerDiagnosticsSelector.candidateIndices(in: candidates).map {
      candidates[$0]
    }
  }

  private func collectVisibleModelMenuItems() -> [CodexVisibleMenuItemMetadata] {
    guard let menu = visiblePopupMenu() else { return [] }
    var queue = [menu]
    var cursor = 0
    var items: [CodexVisibleMenuItemMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      let actions = actionNames(of: element)
      items.append(
        CodexVisibleMenuItemMetadata(
          role: role,
          label: elementLabel(element),
          isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
          supportsPress: actions.contains(kAXPressAction as String)
        )
      )
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return CodexVisibleMenuItemSelector.candidateIndices(in: items).map { items[$0] }
  }

  private func collectVisibleModelOverlayElements() -> [CodexModelOverlayElementMetadata] {
    guard let application = applicationElement(),
      let window = targetWindow(),
      let windowOrigin = pointAttribute(kAXPositionAttribute, from: window),
      let windowSize = sizeAttribute(kAXSizeAttribute, from: window),
      windowSize.width > 0, windowSize.height > 0
    else { return [] }

    var queue = [application]
    var cursor = 0
    var elements: [CodexModelOverlayElementMetadata] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      if let origin = pointAttribute(kAXPositionAttribute, from: element),
        let size = sizeAttribute(kAXSizeAttribute, from: element)
      {
        elements.append(
          CodexModelOverlayElementMetadata(
            role: attribute(kAXRoleAttribute, from: element) ?? "",
            label: elementLabel(element),
            value: attribute(kAXValueAttribute, from: element) ?? "",
            identifier: attribute(kAXIdentifierAttribute, from: element) ?? "",
            relativeX: (origin.x - windowOrigin.x) / windowSize.width,
            relativeY: (origin.y - windowOrigin.y) / windowSize.height,
            width: size.width,
            height: size.height,
            actions: actionNames(of: element)
          ))
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }

    return CodexModelOverlayDiagnosticsSelector.candidateIndices(in: elements)
      .map { elements[$0] }
      .sorted {
        if $0.relativeY == $1.relativeY { return $0.relativeX < $1.relativeX }
        return $0.relativeY < $1.relativeY
      }
      .prefix(500)
      .map { $0 }
  }

  private func navigateVisibleModelMenu(
    _ navigation: ModelMenuNavigationAction
  ) -> CodexUIActionOutcome {
    guard let menu = visiblePopupMenu() else {
      modelMenuSelectionIndex = nil
      return .targetNotFound
    }

    if navigation == .cancel || navigation == .back {
      modelMenuSelectionIndex = nil
      if AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success {
        return .success
      }
      return postEscape() ? .success : .actionFailed
    }

    let items = visibleModelMenuItemElements(in: menu)
    guard !items.isEmpty else { return .targetNotFound }

    if navigation == .confirm || navigation == .enter {
      let index = modelMenuSelectionIndex ?? markedOrFocusedMenuItemIndex(in: items) ?? 0
      modelMenuSelectionIndex = nil
      return click(items[index])
    }

    let step = navigation == .up ? -1 : 1
    let current = modelMenuSelectionIndex ?? markedOrFocusedMenuItemIndex(in: items)
    guard
      let destination = CodexModelMenuSelection.destinationIndex(
        current: current,
        count: items.count,
        step: step
      ),
      let origin = pointAttribute(kAXPositionAttribute, from: items[destination]),
      let size = sizeAttribute(kAXSizeAttribute, from: items[destination]),
      clicker.hover(origin: origin, size: size)
    else { return .actionFailed }

    modelMenuSelectionIndex = destination
    return .success
  }

  private func navigateVisiblePermissionMenu(
    _ navigation: ModelMenuNavigationAction
  ) -> CodexUIActionOutcome {
    guard let menu = visiblePermissionMenu() else {
      permissionMenuSelectionIndex = nil
      return .targetNotFound
    }

    if navigation == .cancel || navigation == .back {
      permissionMenuSelectionIndex = nil
      _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
      return CodexPermissionMenuCancellation.resolve(
        menuIsStillVisible: visiblePermissionMenu() != nil,
        fallbackEscape: postEscape
      )
    }

    let items = permissionMenuItemElements(in: menu)
    guard !items.isEmpty else { return .targetNotFound }

    if navigation == .confirm || navigation == .enter {
      let index =
        permissionMenuSelectionIndex ?? markedOrFocusedMenuItemIndex(in: items) ?? 0
      permissionMenuSelectionIndex = nil
      return click(items[index])
    }

    let step = navigation == .up ? -1 : 1
    let current = permissionMenuSelectionIndex ?? markedOrFocusedMenuItemIndex(in: items)
    guard
      let destination = CodexModelMenuSelection.destinationIndex(
        current: current,
        count: items.count,
        step: step
      ),
      let origin = pointAttribute(kAXPositionAttribute, from: items[destination]),
      let size = sizeAttribute(kAXSizeAttribute, from: items[destination]),
      clicker.hover(origin: origin, size: size)
    else { return .actionFailed }

    permissionMenuSelectionIndex = destination
    return .success
  }

  private func permissionMenuItemElements(in menu: AXUIElement) -> [AXUIElement] {
    var queue = [menu]
    var cursor = 0
    var elements: [AXUIElement] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      let isEnabled: Bool = attribute(kAXEnabledAttribute, from: element) ?? false
      if role == kAXMenuItemRole as String,
        isEnabled,
        actionNames(of: element).contains(kAXPressAction as String),
        !elementLabel(element).isEmpty
      {
        elements.append(element)
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return elements
  }

  private func visibleModelMenuItemElements(in menu: AXUIElement) -> [AXUIElement] {
    var queue = [menu]
    var cursor = 0
    var elements: [AXUIElement] = []
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1
      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      let isEnabled: Bool = attribute(kAXEnabledAttribute, from: element) ?? false
      if [kAXMenuItemRole as String, kAXButtonRole as String].contains(role),
        isEnabled,
        actionNames(of: element).contains(kAXPressAction as String),
        !elementLabel(element).isEmpty
      {
        elements.append(element)
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return elements
  }

  private func markedOrFocusedMenuItemIndex(in items: [AXUIElement]) -> Int? {
    items.firstIndex { element in
      let isFocused: Bool = attribute(kAXFocusedAttribute, from: element) ?? false
      let mark: String = attribute(kAXMenuItemMarkCharAttribute, from: element) ?? ""
      return isFocused || !mark.isEmpty
    }
  }

  private func postEscape() -> Bool {
    guard
      let down = CGEvent(
        keyboardEventSource: CGEventSource(stateID: .hidSystemState),
        virtualKey: CGKeyCode(kVK_Escape),
        keyDown: true
      ),
      let up = CGEvent(
        keyboardEventSource: CGEventSource(stateID: .hidSystemState),
        virtualKey: CGKeyCode(kVK_Escape),
        keyDown: false
      )
    else { return false }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }

  private func clickControl(
    descriptions: [String],
    titles: [String],
    roles: [String]
  ) -> CodexUIActionOutcome {
    guard let element = findElement(descriptions: descriptions, titles: titles, roles: roles) else {
      return .targetNotFound
    }
    return click(element)
  }

  private func clickMenuItem(containing labels: [String]) -> CodexUIActionOutcome {
    guard
      let element = findElement(
        descriptions: [],
        titles: labels,
        roles: [kAXMenuItemRole, kAXButtonRole]
      )
    else { return .targetNotFound }
    return click(element)
  }

  private func click(_ element: AXUIElement) -> CodexUIActionOutcome {
    guard
      let origin = pointAttribute(kAXPositionAttribute, from: element),
      let size = sizeAttribute(kAXSizeAttribute, from: element),
      clicker.click(origin: origin, size: size)
    else { return .actionFailed }
    return .success
  }

  private func press(_ element: AXUIElement) -> CodexUIActionOutcome {
    let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
    return error == .success ? .success : .actionFailed
  }

  private func findMenuItem(path: [String]) -> AXUIElement? {
    guard path.count >= 2, let application = applicationElement() else { return nil }
    guard let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, from: application) else {
      return nil
    }
    guard let menu = descendant(named: path[0], under: menuBar) else { return nil }
    var current = menu
    for label in path.dropFirst() {
      guard let next = descendant(named: label, under: current) else { return nil }
      current = next
    }
    return current
  }

  func codexWindowMenuItems() -> [AXUIElement] {
    guard let application = applicationElement(),
      let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, from: application),
      let windowMenu = ["Window", "窗口"].compactMap({ descendant(named: $0, under: menuBar) })
        .first
    else { return [] }

    let menus: [AXUIElement] = attribute(kAXChildrenAttribute, from: windowMenu) ?? []
    let items = menus.flatMap { menu -> [AXUIElement] in
      attribute(kAXChildrenAttribute, from: menu) ?? []
    }
    let metadata = items.map { item in
      let role: String = attribute(kAXRoleAttribute, from: item) ?? ""
      let identifier: String = attribute(kAXIdentifierAttribute, from: item) ?? ""
      let isEnabled: Bool = attribute(kAXEnabledAttribute, from: item) ?? false
      let mark: String = attribute(kAXMenuItemMarkCharAttribute, from: item) ?? ""
      return CodexWindowMenuItemMetadata(
        role: role,
        identifier: identifier,
        isEnabled: isEnabled,
        isCurrent: !mark.isEmpty
      )
    }
    return CodexWindowMenuSelector.candidateIndices(in: metadata).map { items[$0] }
  }

  private func descendant(named label: String, under element: AXUIElement) -> AXUIElement? {
    var queue: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
    var cursor = 0
    while cursor < queue.count && cursor < maximumElementCount {
      let candidate = queue[cursor]
      cursor += 1
      if labelsMatch(elementLabel(candidate), label) { return candidate }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: candidate) {
        queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
      }
    }
    return nil
  }

  private func labelsMatch(_ actual: String, _ expected: String) -> Bool {
    let normalizedActual = actual.replacingOccurrences(of: "…", with: "...")
    let normalizedExpected = expected.replacingOccurrences(of: "…", with: "...")
    return normalizedActual.localizedCaseInsensitiveCompare(normalizedExpected) == .orderedSame
  }

  private func findElement(
    descriptions: [String],
    titles: [String],
    roles: [String]
  ) -> AXUIElement? {
    var roots: [AXUIElement] = []
    if let window = targetWindow() { roots.append(window) }
    if let application = applicationElement() { roots.append(application) }
    for root in roots {
      var queue = [root]
      var cursor = 0
      while cursor < queue.count && cursor < maximumElementCount {
        let element = queue[cursor]
        cursor += 1
        let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
        let title = elementLabel(element)
        let description: String = attribute(kAXDescriptionAttribute, from: element) ?? ""
        let titleMatches = titles.contains { title.localizedCaseInsensitiveContains($0) }
        let descriptionMatches = descriptions.contains {
          description.localizedCaseInsensitiveContains($0)
        }
        let hasLabelFilter = !titles.isEmpty || !descriptions.isEmpty
        if roles.contains(role) && (!hasLabelFilter || titleMatches || descriptionMatches) {
          return element
        }
        if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
          queue.append(contentsOf: children.prefix(maximumElementCount - queue.count))
        }
      }
    }
    return nil
  }

  private func targetWindow() -> AXUIElement? {
    guard let application = applicationElement() else { return nil }
    if let focused: AXUIElement = attribute(kAXFocusedWindowAttribute, from: application) {
      return focused
    }
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: application) ?? []
    return windows.first
  }

  func applicationElement() -> AXUIElement? {
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).first
    else { return nil }
    return AXUIElementCreateApplication(application.processIdentifier)
  }

  private func elementLabel(_ element: AXUIElement) -> String {
    let title: String = attribute(kAXTitleAttribute, from: element) ?? ""
    if !title.isEmpty { return title }
    return attribute(kAXDescriptionAttribute, from: element) ?? ""
  }

  private func actionNames(of element: AXUIElement) -> [String] {
    var values: CFArray?
    guard AXUIElementCopyActionNames(element, &values) == .success else { return [] }
    return values as? [String] ?? []
  }

  func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value as? T
  }

  private func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool {
    var settable: DarwinBoolean = false
    guard
      AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
    else { return false }
    return settable.boolValue
  }

  func pointAttribute(_ name: String, from element: AXUIElement) -> CGPoint? {
    guard let value: AXValue = attribute(name, from: element) else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
    return point
  }

  func sizeAttribute(_ name: String, from element: AXUIElement) -> CGSize? {
    guard let value: AXValue = attribute(name, from: element) else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else { return nil }
    return size
  }

  private func rangeAttribute(_ name: String, from element: AXUIElement) -> NSRange? {
    guard let value: AXValue = attribute(name, from: element),
      AXValueGetType(value) == .cfRange
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else {
      return nil
    }
    return NSRange(location: range.location, length: range.length)
  }

  private func axRangeValue(_ range: NSRange) -> AXValue? {
    var value = CFRange(location: range.location, length: range.length)
    return AXValueCreate(.cfRange, &value)
  }

  func onMain<T>(_ operation: () -> T) -> T {
    if Thread.isMainThread { return operation() }
    return DispatchQueue.main.sync(execute: operation)
  }
}
