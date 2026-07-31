import AppKit
import ApplicationServices
import Foundation
import XboxCodexBridgeCore

enum CodexAccessibilityPressOutcome: Equatable {
  case success
  case controlNotFound
  case pressFailed
  case stateUnchanged
}

enum CodexAccessibilityPressPlan {
  static func perform(
    axPress: () -> Bool,
    verifyAfterAXPress: () -> Bool,
    fallbackPointerClick: () -> Bool,
    verifyAfterPointerClick: () -> Bool
  ) -> CodexAccessibilityPressOutcome {
    var attempted = false
    if axPress() {
      attempted = true
      if verifyAfterAXPress() { return .success }
    }
    if fallbackPointerClick() {
      attempted = true
      if verifyAfterPointerClick() { return .success }
    }
    return attempted ? .stateUnchanged : .pressFailed
  }
}

struct CodexDictationWindowDiagnostic: Codable, Equatable {
  let title: String
  let role: String
  let width: Double
  let height: Double
  let isFocused: Bool
  let isMain: Bool
}

struct CodexDictationButtonDiagnostic: Codable, Equatable {
  let identifier: String
  let title: String
  let description: String
  let isEnabled: Bool
  let supportsPress: Bool
}

struct CodexDictationDiagnostics: Codable, Equatable {
  let accessibilityTrusted: Bool
  let codexIsRunning: Bool
  let windows: [CodexDictationWindowDiagnostic]
  let inspectedWindowTitle: String?
  let buttons: [CodexDictationButtonDiagnostic]

  init(
    accessibilityTrusted: Bool,
    codexIsRunning: Bool,
    windows: [CodexDictationWindowDiagnostic],
    inspectedWindowTitle: String? = nil,
    buttons: [CodexDictationButtonDiagnostic]
  ) {
    self.accessibilityTrusted = accessibilityTrusted
    self.codexIsRunning = codexIsRunning
    self.windows = windows
    self.inspectedWindowTitle = inspectedWindowTitle
    self.buttons = buttons
  }
}

protocol CodexAccessibilityClient: AnyObject {
  var isTrusted: Bool { get }

  func activateCodex() -> Bool
  func pressAndVerify(_ phase: CodexDictationPhase) -> CodexAccessibilityPressOutcome
  func diagnostics() -> CodexDictationDiagnostics
}

protocol PointerEventDriving: AnyObject {
  var currentLocation: CGPoint? { get }

  func move(to point: CGPoint) -> Bool
  func leftMouseDown(at point: CGPoint) -> Bool
  func leftMouseUp(at point: CGPoint) -> Bool
}

final class CodexPointerClicker {
  private let driver: PointerEventDriving

  init(driver: PointerEventDriving) {
    self.driver = driver
  }

  func click(origin: CGPoint, size: CGSize) -> Bool {
    guard let originalLocation = driver.currentLocation, size.width > 0, size.height > 0 else {
      return false
    }
    defer { _ = driver.move(to: originalLocation) }

    let center = CGPoint(
      x: origin.x + size.width / 2,
      y: origin.y + size.height / 2
    )
    return driver.move(to: center)
      && driver.leftMouseDown(at: center)
      && driver.leftMouseUp(at: center)
  }

  func hover(origin: CGPoint, size: CGSize) -> Bool {
    guard size.width > 0, size.height > 0 else { return false }
    return driver.move(
      to: CGPoint(
        x: origin.x + size.width / 2,
        y: origin.y + size.height / 2
      ))
  }
}

final class SystemPointerEventDriver: PointerEventDriving {
  var currentLocation: CGPoint? {
    CGEvent(source: nil)?.location
  }

  func move(to point: CGPoint) -> Bool {
    post(type: .mouseMoved, at: point)
  }

  func leftMouseDown(at point: CGPoint) -> Bool {
    post(type: .leftMouseDown, at: point)
  }

  func leftMouseUp(at point: CGPoint) -> Bool {
    post(type: .leftMouseUp, at: point)
  }

  private func post(type: CGEventType, at point: CGPoint) -> Bool {
    guard
      let event = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    else {
      return false
    }
    event.post(tap: .cghidEventTap)
    return true
  }
}

final class CodexDictationController {
  private let client: CodexAccessibilityClient
  private let queue = DispatchQueue(label: "XboxCodexBridge.CodexDictationController")
  private let readinessAttempts: Int
  private let readinessInterval: TimeInterval
  private let sleep: (TimeInterval) -> Void

  init(
    client: CodexAccessibilityClient,
    readinessAttempts: Int = 80,
    readinessInterval: TimeInterval = 0.1,
    sleep: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
  ) {
    self.client = client
    self.readinessAttempts = max(1, readinessAttempts)
    self.readinessInterval = max(0, readinessInterval)
    self.sleep = sleep
  }

  func diagnostics() -> CodexDictationDiagnostics {
    client.diagnostics()
  }

  func perform(
    _ phase: CodexDictationPhase,
    completion: @escaping (DispatchResult) -> Void
  ) {
    guard client.isTrusted else {
      completion(
        DispatchResult(
          accepted: false,
          message: "Enable Accessibility before using dictation"
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
        completion(
          DispatchResult(
            accepted: false,
            message: "Codex dictation button is unavailable"
          ))
        return
      }

      var pressOutcome = CodexAccessibilityPressOutcome.controlNotFound
      for attempt in 0..<readinessAttempts {
        pressOutcome = client.pressAndVerify(phase)
        if pressOutcome != .controlNotFound { break }
        if attempt < readinessAttempts - 1 { sleep(readinessInterval) }
      }

      let result: DispatchResult
      switch pressOutcome {
      case .success:
        result = DispatchResult(
          accepted: true,
          message: phase == .start ? "Codex dictation started" : "Codex dictation stopped"
        )
      case .controlNotFound:
        result = DispatchResult(
          accepted: false,
          message: "Codex dictation button is unavailable"
        )
      case .pressFailed:
        result = DispatchResult(
          accepted: false,
          message: "Codex rejected the dictation button press"
        )
      case .stateUnchanged:
        result = DispatchResult(
          accepted: false,
          message: phase == .start
            ? "Codex did not enter dictation mode"
            : "Codex did not stop dictation"
        )
      }
      completion(result)
    }
  }
}

final class SystemCodexAccessibilityClient: CodexAccessibilityClient {
  private let bundleIdentifier = "com.openai.codex"
  private let maximumElementCount = 10_000
  private let clicker: CodexPointerClicker

  init(clicker: CodexPointerClicker = CodexPointerClicker(driver: SystemPointerEventDriver())) {
    self.clicker = clicker
  }

  var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  func activateCodex() -> Bool {
    onMain {
      guard
        let application = NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleIdentifier
        ).first
      else {
        return false
      }
      CodexAccessibilityBootstrap.enableApplicationAccessibility(
        for: application.processIdentifier
      )
      return application.activate(options: [.activateAllWindows])
    }
  }

  func pressAndVerify(_ phase: CodexDictationPhase) -> CodexAccessibilityPressOutcome {
    guard let control = findControl(for: phase) else {
      return .controlNotFound
    }
    let expectedPhase: CodexDictationPhase = phase == .start ? .stop : .start
    return CodexAccessibilityPressPlan.perform(
      axPress: {
        AXUIElementPerformAction(control, kAXPressAction as CFString) == .success
      },
      verifyAfterAXPress: {
        self.waitForControl(for: expectedPhase, attempts: 6)
      },
      fallbackPointerClick: {
        guard
          let origin = self.pointAttribute(kAXPositionAttribute, from: control),
          let size = self.sizeAttribute(kAXSizeAttribute, from: control)
        else { return false }
        return self.clicker.click(origin: origin, size: size)
      },
      verifyAfterPointerClick: {
        self.waitForControl(for: expectedPhase, attempts: 30)
      }
    )
  }

  func diagnostics() -> CodexDictationDiagnostics {
    let accessibilityTrusted = isTrusted
    guard let application = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).first else {
      return CodexDictationDiagnostics(
        accessibilityTrusted: accessibilityTrusted,
        codexIsRunning: false,
        windows: [],
        buttons: []
      )
    }

    let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: applicationElement) ?? []
    let focusedWindow: AXUIElement? = attribute(kAXFocusedWindowAttribute, from: applicationElement)
    let windowMetadata = windows.map { window in
      CodexWindowMetadata(
        title: attribute(kAXTitleAttribute, from: window) ?? "",
        size: sizeAttribute(kAXSizeAttribute, from: window) ?? .zero,
        isFocused: focusedWindow.map { CFEqual($0, window) } ?? false,
        isMain: attribute(kAXMainAttribute, from: window) ?? false
      )
    }
    let windowDiagnostics = windowMetadata.map {
      CodexDictationWindowDiagnostic(
        title: $0.title,
        role: "AXWindow",
        width: Double($0.size.width),
        height: Double($0.size.height),
        isFocused: $0.isFocused,
        isMain: $0.isMain
      )
    }
    let inspectionIndex = CodexWindowSelector.bestIndex(in: windowMetadata)
      ?? windowMetadata.firstIndex(where: \.isFocused)
      ?? windowMetadata.indices.max { left, right in
        let leftArea = windowMetadata[left].size.width * windowMetadata[left].size.height
        let rightArea = windowMetadata[right].size.width * windowMetadata[right].size.height
        return leftArea < rightArea
      }

    guard let inspectionIndex, windows.indices.contains(inspectionIndex) else {
      return CodexDictationDiagnostics(
        accessibilityTrusted: accessibilityTrusted,
        codexIsRunning: true,
        windows: windowDiagnostics,
        buttons: []
      )
    }

    return CodexDictationDiagnostics(
      accessibilityTrusted: accessibilityTrusted,
      codexIsRunning: true,
      windows: windowDiagnostics,
      inspectedWindowTitle: windowMetadata[inspectionIndex].title,
      buttons: buttonDiagnostics(in: windows[inspectionIndex])
    )
  }

  private func waitForControl(
    for phase: CodexDictationPhase,
    attempts: Int
  ) -> Bool {
    for _ in 0..<attempts {
      if findControl(for: phase) != nil {
        return true
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return false
  }

  private func findControl(for phase: CodexDictationPhase) -> AXUIElement? {
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).first
    else {
      return nil
    }

    let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: applicationElement) ?? []
    let focusedWindow: AXUIElement? = attribute(kAXFocusedWindowAttribute, from: applicationElement)
    let windowMetadata = windows.map { window in
      CodexWindowMetadata(
        title: attribute(kAXTitleAttribute, from: window) ?? "",
        size: sizeAttribute(kAXSizeAttribute, from: window) ?? .zero,
        isFocused: focusedWindow.map { CFEqual($0, window) } ?? false,
        isMain: attribute(kAXMainAttribute, from: window) ?? false
      )
    }
    guard let targetIndex = CodexWindowSelector.bestIndex(in: windowMetadata) else {
      return nil
    }
    let targetWindow = windows[targetIndex]

    var queue = [targetWindow]
    var cursor = 0
    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1

      if DictationAccessibilityMatcher.matches(metadata(for: element), phase: phase) {
        return element
      }
      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        let remainingCapacity = maximumElementCount - queue.count
        if remainingCapacity > 0 {
          queue.append(contentsOf: children.prefix(remainingCapacity))
        }
      }
    }
    return nil
  }

  private func buttonDiagnostics(in root: AXUIElement) -> [CodexDictationButtonDiagnostic] {
    var queue = [root]
    var cursor = 0
    var buttons: [CodexDictationButtonDiagnostic] = []

    while cursor < queue.count && cursor < maximumElementCount {
      let element = queue[cursor]
      cursor += 1

      let role: String = attribute(kAXRoleAttribute, from: element) ?? ""
      if role == kAXButtonRole as String {
        buttons.append(
          CodexDictationButtonDiagnostic(
            identifier: attribute(kAXIdentifierAttribute, from: element) ?? "",
            title: attribute(kAXTitleAttribute, from: element) ?? "",
            description: attribute(kAXDescriptionAttribute, from: element) ?? "",
            isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
            supportsPress: actionNames(for: element).contains(kAXPressAction as String)
          ))
      }

      if let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) {
        let remainingCapacity = maximumElementCount - queue.count
        if remainingCapacity > 0 {
          queue.append(contentsOf: children.prefix(remainingCapacity))
        }
      }
    }
    return buttons
  }

  private func metadata(for element: AXUIElement) -> AccessibilityControlMetadata {
    AccessibilityControlMetadata(
      role: attribute(kAXRoleAttribute, from: element) ?? "",
      identifier: attribute(kAXIdentifierAttribute, from: element) ?? "",
      title: attribute(kAXTitleAttribute, from: element) ?? "",
      description: attribute(kAXDescriptionAttribute, from: element) ?? "",
      isEnabled: attribute(kAXEnabledAttribute, from: element) ?? false,
      actions: actionNames(for: element)
    )
  }

  private func actionNames(for element: AXUIElement) -> [String] {
    var value: CFArray?
    guard AXUIElementCopyActionNames(element, &value) == .success else {
      return []
    }
    return value as? [String] ?? []
  }

  private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value as? T
  }

  private func pointAttribute(_ name: String, from element: AXUIElement) -> CGPoint? {
    guard let value: AXValue = attribute(name, from: element) else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
    return point
  }

  private func sizeAttribute(_ name: String, from element: AXUIElement) -> CGSize? {
    guard let value: AXValue = attribute(name, from: element) else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else { return nil }
    return size
  }

  private func onMain<T>(_ operation: () -> T) -> T {
    if Thread.isMainThread {
      return operation()
    }
    return DispatchQueue.main.sync(execute: operation)
  }
}
