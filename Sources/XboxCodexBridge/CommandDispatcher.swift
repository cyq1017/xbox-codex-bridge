import Carbon.HIToolbox
import CoreGraphics
import Foundation
import XboxCodexBridgeCore

struct DispatchResult {
  let accepted: Bool
  let message: String
}

struct PlainKeyDispatchPlan {
  let keys: [String]
  let interKeyDelay: TimeInterval

  init(actionID: String, key: String) {
    if actionID == "cancel" {
      keys = [key, key]
      interKeyDelay = 0.12
    } else {
      keys = [key]
      interKeyDelay = 0
    }
  }
}

enum ModelMenuKeyboardPlan {
  static func key(for navigation: ModelMenuNavigationAction) -> String {
    switch navigation {
    case .up: return "up"
    case .down: return "down"
    case .enter: return "right"
    case .back: return "left"
    case .confirm: return "return"
    case .cancel: return "escape"
    }
  }
}

final class CommandDispatcher {
  private let queue = DispatchQueue(label: "XboxCodexBridge.CommandDispatcher")
  private let uiController: CodexUIActionController

  init(
    uiController: CodexUIActionController = CodexUIActionController(
      client: SystemCodexUIActionClient()
    )
  ) {
    self.uiController = uiController
  }

  var isAccessibilityTrusted: Bool {
    uiController.isAccessibilityTrusted
  }

  func requestAccessibilityIfNeeded() {
    uiController.requestAccessibilityIfNeeded()
  }

  func codexWindows() -> [CodexWindowInfo] {
    uiController.codexWindows()
  }

  func focusCodexWindow(id: String) -> Bool {
    uiController.focusCodexWindow(id: id)
  }

  func codexWindowMenuEntries() -> [CodexWindowMenuEntry] {
    uiController.codexWindowMenuEntries()
  }

  func modelPickerCandidates() -> [CodexModelPickerCandidateMetadata] {
    uiController.modelPickerCandidates()
  }

  func visibleModelMenuItems() -> [CodexVisibleMenuItemMetadata] {
    uiController.visibleModelMenuItems()
  }

  func visibleModelOverlayElements() -> [CodexModelOverlayElementMetadata] {
    uiController.visibleModelOverlayElements()
  }

  func isPermissionMenuVisible() -> Bool {
    uiController.isPermissionMenuVisible()
  }

  func focusCodexWindowMenuEntry(id: String) -> Bool {
    uiController.focusCodexWindowMenuEntry(id: id)
  }

  func performModelMenuNavigation(
    _ navigation: ModelMenuNavigationAction,
    completion: @escaping (DispatchResult) -> Void
  ) {
    queue.async { [weak self] in
      guard let self else { return }
      self.postKey(ModelMenuKeyboardPlan.key(for: navigation), modifiers: [])
      completion(
        DispatchResult(accepted: true, message: "Sent model-menu keyboard navigation.")
      )
    }
  }

  func performPermissionMenuNavigation(
    _ navigation: ModelMenuNavigationAction,
    completion: @escaping (DispatchResult) -> Void
  ) {
    uiController.performPermissionMenuNavigation(navigation, completion: completion)
  }

  func perform(_ action: ActionDefinition, completion: @escaping (DispatchResult) -> Void) {
    if action.id == "launchCodex" {
      queue.async { [weak self] in
        guard let self else { return }
        guard self.uiController.activateCodex() else {
          completion(DispatchResult(accepted: false, message: "Codex App is not installed"))
          return
        }
        completion(DispatchResult(accepted: true, message: "Codex is ready."))
      }
      return
    }

    guard isAccessibilityTrusted else {
      completion(
        DispatchResult(
          accepted: false,
          message: "Enable Accessibility for the bridge before sending Codex commands"
        ))
      return
    }

    switch action.dispatch.kind {
    case .plainKey:
      queue.async { [weak self] in
        guard let self else { return }
        guard self.uiController.activateCodex() else {
          completion(DispatchResult(accepted: false, message: "Codex App is not installed"))
          return
        }
        Thread.sleep(forTimeInterval: 0.12)
        guard let key = action.dispatch.key else {
          completion(DispatchResult(accepted: false, message: "Action has no key binding"))
          return
        }
        let plan = PlainKeyDispatchPlan(actionID: action.id, key: key)
        for (index, plannedKey) in plan.keys.enumerated() {
          if index > 0 {
            Thread.sleep(forTimeInterval: plan.interKeyDelay)
          }
          self.postKey(plannedKey, modifiers: [])
        }
        completion(
          DispatchResult(
            accepted: true,
            message: "Sent \(action.label)."
          ))
      }
    case .keystroke:
      queue.async { [weak self] in
        guard let self else { return }
        guard self.uiController.activateCodex() else {
          completion(DispatchResult(accepted: false, message: "Codex App is not installed"))
          return
        }
        Thread.sleep(forTimeInterval: 0.12)
        guard let key = action.dispatch.key else {
          completion(DispatchResult(accepted: false, message: "Action has no key binding"))
          return
        }
        self.postKey(key, modifiers: action.dispatch.modifiers)
        completion(
          DispatchResult(
            accepted: true,
            message: "Requested \(action.label)."
          ))
      }
    case .pushToTalk:
      completion(
        DispatchResult(
          accepted: false,
          message: "Push to talk requires a physical press or release event"
        ))
    default:
      uiController.perform(action, completion: completion)
    }
  }

  private func postKey(_ name: String, modifiers: [String]) {
    postKeyEvent(name, modifiers: modifiers, isKeyDown: true)
    postKeyEvent(name, modifiers: modifiers, isKeyDown: false)
  }

  private func postKeyEvent(_ name: String, modifiers: [String], isKeyDown: Bool) {
    guard let keyCode = keyCode(for: name) else { return }
    let event = CGEvent(
      keyboardEventSource: CGEventSource(stateID: .hidSystemState),
      virtualKey: keyCode,
      keyDown: isKeyDown
    )
    event?.flags = modifierFlags(for: modifiers)
    event?.post(tap: .cghidEventTap)
  }

  private func modifierFlags(for names: [String]) -> CGEventFlags {
    names.reduce(into: CGEventFlags()) { flags, name in
      switch name {
      case "command": flags.insert(.maskCommand)
      case "shift": flags.insert(.maskShift)
      case "control": flags.insert(.maskControl)
      case "option": flags.insert(.maskAlternate)
      default: break
      }
    }
  }

  private func keyCode(for name: String) -> CGKeyCode? {
    let codes: [String: Int] = [
      "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C,
      "d": kVK_ANSI_D, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
      "j": kVK_ANSI_J, "k": kVK_ANSI_K, "m": kVK_ANSI_M,
      "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
      "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
      "u": kVK_ANSI_U, "1": kVK_ANSI_1, "2": kVK_ANSI_2,
      "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
      "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
      "9": kVK_ANSI_9, "[": kVK_ANSI_LeftBracket,
      "]": kVK_ANSI_RightBracket, ",": kVK_ANSI_Comma,
      "/": kVK_ANSI_Slash, "grave": kVK_ANSI_Grave,
      "return": kVK_Return, "escape": kVK_Escape,
      "f13": kVK_F13,
      "control": kVK_Control, "option": kVK_Option,
      "shift": kVK_Shift, "command": kVK_Command,
      "up": kVK_UpArrow, "down": kVK_DownArrow,
      "left": kVK_LeftArrow, "right": kVK_RightArrow,
    ]
    guard let value = codes[name] else { return nil }
    return CGKeyCode(value)
  }
}
