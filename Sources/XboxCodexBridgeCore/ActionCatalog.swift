import Foundation

public enum DispatchKind: String, Codable, Equatable, Sendable {
  case plainKey
  case nativeMenu
  case uiControl
  case unavailable
  case shortcut
  case keystroke
  case commandPalette
  case pushToTalk
}

public struct DispatchRecipe: Codable, Equatable, Sendable {
  public let kind: DispatchKind
  public let key: String?
  public let modifiers: [String]
  public let commandTitle: String?
  public let menuPath: [String]?
  public let uiControlID: String?
  public let unavailableReason: String?
  public let requiresShortcutSetup: Bool

  public init(
    kind: DispatchKind,
    key: String? = nil,
    modifiers: [String] = [],
    commandTitle: String? = nil,
    menuPath: [String]? = nil,
    uiControlID: String? = nil,
    unavailableReason: String? = nil,
    requiresShortcutSetup: Bool = false
  ) {
    self.kind = kind
    self.key = key
    self.modifiers = modifiers
    self.commandTitle = commandTitle
    self.menuPath = menuPath
    self.uiControlID = uiControlID
    self.unavailableReason = unavailableReason
    self.requiresShortcutSetup = requiresShortcutSetup
  }
}

public struct ActionDefinition: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let category: String
  public let dispatch: DispatchRecipe
  public let holdDuration: TimeInterval?
  public let isSafeForWebTest: Bool

  public init(
    id: String,
    label: String,
    category: String,
    dispatch: DispatchRecipe,
    holdDuration: TimeInterval? = nil,
    isSafeForWebTest: Bool = true
  ) {
    self.id = id
    self.label = label
    self.category = category
    self.dispatch = dispatch
    self.holdDuration = holdDuration
    self.isSafeForWebTest = isSafeForWebTest && holdDuration == nil
  }
}

public enum ActionCatalog {
  public static let all: [ActionDefinition] = [
    pushToTalkAction(),
    key("submit", "Send composer", "Input", "return", safeForWebTest: false),
    key(
      "submitWithNotification", "Send and notify on completion", "Input", "return",
      safeForWebTest: false),
    keystroke(
      "insertNewline", "Insert new line", "Input", "return", ["shift"], safeForWebTest: false),
    key("cancel", "Cancel / close", "Input", "escape"),
    uiControl("focusComposer", "Focus composer", "Input"),
    uiControl("clearComposer", "Clear composer", "Input", safeForWebTest: false),
    uiControl("composerMoveLeft", "Move cursor left", "Input", safeForWebTest: false),
    uiControl("composerMoveRight", "Move cursor right", "Input", safeForWebTest: false),
    uiControl(
      "composerMoveLineStart", "Move to line start", "Input", safeForWebTest: false),
    uiControl("composerMoveLineEnd", "Move to line end", "Input", safeForWebTest: false),
    uiControl("composerSelectLeft", "Select left", "Input", safeForWebTest: false),
    uiControl("composerSelectRight", "Select right", "Input", safeForWebTest: false),
    uiControl(
      "composerSelectLineStart", "Select to line start", "Input", safeForWebTest: false),
    uiControl(
      "composerSelectLineEnd", "Select to line end", "Input", safeForWebTest: false),
    uiControl(
      "composerDeleteBackward", "Delete selection / previous character", "Input",
      safeForWebTest: false),
    uiControl(
      "selectionAddToTask", "Add selected output to task", "Output", safeForWebTest: false),
    uiControl(
      "selectionAskSideChat", "Ask about selection in side chat", "Output",
      safeForWebTest: false),
    uiControl(
      "selectionMoreDetails", "Show more details for selection", "Output",
      safeForWebTest: false),
    key("composerSelect", "Open / select composer control", "Input", "return"),
    key("composerPrevious", "Previous composer control", "Input", "up"),
    key("composerNext", "Next composer control", "Input", "down"),
    keystroke(
      "modelPicker", "Open model & reasoning", "Reasoning", "m", ["control", "shift"]),
    uiControl(
      "permissionPicker", "Open permission mode", "Safety", safeForWebTest: false),
    uiControl("reasoningIncrease", "Increase reasoning effort", "Reasoning"),
    uiControl("reasoningDecrease", "Decrease reasoning effort", "Reasoning"),
    uiControl("reasoningCycle", "Cycle reasoning effort", "Reasoning"),
    uiControl("fastToggle", "Toggle Fast mode", "Reasoning"),
    uiControl("planToggle", "Toggle Plan mode", "Reasoning"),
    uiControl("review", "Open review", "Workspace"),
    nativeMenu("terminal", "Toggle terminal", "Workspace", ["View", "Open Terminal"]),
    nativeMenu("browser", "Open browser", "Workspace", ["View", "Open Browser Tab"]),
    nativeMenu(
      "toggleSidePanel", "Toggle side panel", "Workspace", ["View", "Toggle Side Panel"]),
    nativeMenu(
      "toggleBottomPanel", "Toggle bottom panel", "Workspace", ["View", "Toggle Bottom Panel"]),
    nativeMenu(
      "toggleSidebar", "Toggle sidebar", "Workspace", ["View", "Toggle Sidebar"]),
    nativeMenu("openFolder", "Open folder", "Workspace", ["File", "Open Folder…"]),
    palette("gitCommit", "Git commit", "Workspace", "Commit with Git", safeForWebTest: false),
    palette(
      "createPR", "Create pull request", "Workspace", "Create pull request", safeForWebTest: false),
    palette("skills", "Open Skills", "Workspace", "Skills"),
    palette("manageTasks", "Manage scheduled tasks", "Workspace", "Manage tasks"),
    uiControl("addFiles", "Attach files", "Input", safeForWebTest: false),
    uiControl("addPhotos", "Attach photos", "Input", safeForWebTest: false),
    nativeMenu("previousTask", "Previous task", "Tasks", ["View", "Previous Task"]),
    nativeMenu("nextTask", "Next task", "Tasks", ["View", "Next Task"]),
    nativeMenu("newTask", "New task", "Tasks", ["File", "New Chat"]),
    keystroke(
      "newProjectlessTask", "New standalone task", "Tasks", "o", ["command", "option"],
      safeForWebTest: false),
    nativeMenu("newWindow", "New Codex window", "Navigation", ["File", "New Window"]),
    uiControl(
      "newTaskWindow", "New task window in current project", "Navigation",
      safeForWebTest: false),
    shortcut("quickChat", "Quick chat", "Tasks", "n", ["command", "option"]),
    uiControl("searchTasks", "Search tasks", "Tasks"),
    shortcut("sideTask", "Open side task", "Tasks", "s", ["command", "option"]),
    palette("openTaskWindow", "Open task in new window", "Tasks", "Open in New Window"),
    palette(
      "copyMarkdown", "Copy task as Markdown", "Tasks", "Copy as Markdown", safeForWebTest: false),
    nativeMenu(
      "togglePin", "Pin / unpin task", "Tasks", ["View", "Toggle Pinned Summary"]),
    shortcut("archiveTask", "Archive task", "Safety", "a", ["command", "shift"], hold: 0.8),
    key("approve", "Approve request", "Safety", "return", hold: 0.6),
    key("decline", "Decline request", "Safety", "escape", hold: 0.35),
    reserved("fork", "Continue in a new task", "Safety", "k", hold: 0.6),
    nativeMenu("navigateBack", "Navigate back", "Navigation", ["View", "Back"]),
    nativeMenu("navigateForward", "Navigate forward", "Navigation", ["View", "Forward"]),
    uiControl("previousWindow", "Previous Codex window", "Navigation"),
    uiControl("nextWindow", "Next Codex window", "Navigation"),
    uiControl(
      "windowSwitcher", "Show all Codex windows", "Navigation", safeForWebTest: false),
    nativeMenu(
      "newProject", "Create or open independent project", "Navigation",
      ["File", "Open Folder…"], safeForWebTest: false),
    uiControl("launchCodex", "Launch or focus Codex", "System", safeForWebTest: false),
    uiControl("commandMenu", "Open command menu", "Navigation"),
    nativeMenu("settings", "Open settings", "System", ["ChatGPT", "Settings…"]),
    nativeMenu(
      "keyboardShortcuts", "Keyboard shortcuts", "System", ["Help", "Keyboard Shortcuts"]),
    palette("mcpSettings", "MCP settings", "System", "MCP settings"),
    shortcut("processManager", "Process manager", "System", "m", ["control", "option"]),
    palette("reloadSkills", "Reload Skills", "System", "Reload Skills"),
    nativeMenu("feedback", "Send feedback", "System", ["Help", "Send Feedback"]),
    unavailable(
      "environmentAction1", "Environment action 1", "Actions",
      "No verified Codex UI adapter is configured", safeForWebTest: false),
    reserved("environmentAction2", "Environment action 2", "Actions", "2", safeForWebTest: false),
    reserved("environmentAction3", "Environment action 3", "Actions", "3", safeForWebTest: false),
    reserved("environmentAction4", "Environment action 4", "Actions", "4", safeForWebTest: false),
    reserved("environmentAction5", "Environment action 5", "Actions", "5", safeForWebTest: false),
    reserved("environmentAction6", "Environment action 6", "Actions", "6", safeForWebTest: false),
    reserved("environmentAction7", "Environment action 7", "Actions", "7", safeForWebTest: false),
    reserved("environmentAction8", "Environment action 8", "Actions", "8", safeForWebTest: false),
    reserved("environmentAction9", "Environment action 9", "Actions", "9", safeForWebTest: false),
    taskShortcut(1), taskShortcut(2), taskShortcut(3), taskShortcut(4),
    taskShortcut(5), taskShortcut(6),
  ]

  public static func definition(for id: String) -> ActionDefinition? {
    all.first { $0.id == id }
  }

  private static func pushToTalkAction() -> ActionDefinition {
    ActionDefinition(
      id: "pushToTalk",
      label: "Push to talk",
      category: "Input",
      dispatch: DispatchRecipe(kind: .pushToTalk),
      isSafeForWebTest: false
    )
  }

  private static func key(
    _ id: String,
    _ label: String,
    _ category: String,
    _ key: String,
    hold: TimeInterval? = nil,
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(kind: .plainKey, key: key),
      holdDuration: hold,
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func shortcut(
    _ id: String,
    _ label: String,
    _ category: String,
    _ key: String,
    _ modifiers: [String],
    hold: TimeInterval? = nil,
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(kind: .shortcut, key: key, modifiers: modifiers),
      holdDuration: hold,
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func keystroke(
    _ id: String,
    _ label: String,
    _ category: String,
    _ key: String,
    _ modifiers: [String],
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(kind: .keystroke, key: key, modifiers: modifiers),
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func reserved(
    _ id: String,
    _ label: String,
    _ category: String,
    _ key: String,
    hold: TimeInterval? = nil,
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(
        kind: .unavailable,
        key: key,
        unavailableReason: "No verified Codex UI adapter is configured",
        requiresShortcutSetup: true
      ),
      holdDuration: hold,
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func nativeMenu(
    _ id: String,
    _ label: String,
    _ category: String,
    _ menuPath: [String],
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(kind: .nativeMenu, menuPath: menuPath),
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func uiControl(
    _ id: String,
    _ label: String,
    _ category: String,
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(kind: .uiControl, uiControlID: id),
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func unavailable(
    _ id: String,
    _ label: String,
    _ category: String,
    _ reason: String,
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(kind: .unavailable, unavailableReason: reason),
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func palette(
    _ id: String,
    _ label: String,
    _ category: String,
    _ commandTitle: String,
    safeForWebTest: Bool = true
  ) -> ActionDefinition {
    ActionDefinition(
      id: id,
      label: label,
      category: category,
      dispatch: DispatchRecipe(kind: .commandPalette, commandTitle: commandTitle),
      holdDuration: nil,
      isSafeForWebTest: safeForWebTest
    )
  }

  private static func taskShortcut(_ number: Int) -> ActionDefinition {
    shortcut(
      "task\(number)",
      "Task slot \(number)",
      "Tasks",
      String(number),
      ["command"]
    )
  }
}
