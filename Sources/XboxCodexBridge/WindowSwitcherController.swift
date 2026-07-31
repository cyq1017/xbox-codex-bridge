import AppKit
import Foundation
import XboxCodexBridgeCore

struct CodexWindowMenuItemMetadata: Equatable {
  let role: String
  let identifier: String
  let isEnabled: Bool
  let isCurrent: Bool
}

enum CodexWindowMenuSelector {
  static func candidateIndices(in items: [CodexWindowMenuItemMetadata]) -> [Int] {
    items.indices.filter { index in
      let item = items[index]
      return item.role == kAXMenuItemRole as String
        && item.identifier == "makeKeyAndOrderFront:"
        && item.isEnabled
    }
  }

  static func currentCandidateIndex(in items: [CodexWindowMenuItemMetadata]) -> Int? {
    let candidates = candidateIndices(in: items)
    return candidates.firstIndex { items[$0].isCurrent }
  }
}

struct WindowSwitcherState {
  private(set) var selectedIndex = 0
  private let count: Int

  init(count: Int, currentIndex: Int?) {
    self.count = max(0, count)
    guard count > 0 else { return }
    selectedIndex = min(max(currentIndex ?? 0, 0), count - 1)
  }

  mutating func move(step: Int) {
    guard count > 0 else { return }
    let direction = step >= 0 ? 1 : -1
    selectedIndex = (selectedIndex + direction + count) % count
  }
}

struct CodexWindowTitleHistory {
  private(set) var titles: [Int: String] = [:]
  private var windowCount: Int?

  mutating func synchronize(windowCount: Int) {
    guard self.windowCount != windowCount else { return }
    self.windowCount = windowCount
    titles.removeAll()
  }

  mutating func record(_ title: String, at index: Int) {
    titles[index] = title
  }

  subscript(index: Int) -> String? {
    titles[index]
  }
}

final class WindowSwitcherController {
  private var entries: [CodexWindowMenuEntry] = []
  private var state = WindowSwitcherState(count: 0, currentIndex: nil)
  private var selectionHandler: ((CodexWindowMenuEntry) -> Void)?
  private var panel: NSPanel?

  var isPresented: Bool {
    panel?.isVisible == true
  }

  func present(
    entries: [CodexWindowMenuEntry],
    onSelect: @escaping (CodexWindowMenuEntry) -> Void
  ) {
    guard !entries.isEmpty else { return }
    self.entries = entries
    state = WindowSwitcherState(
      count: entries.count,
      currentIndex: entries.firstIndex(where: \.isCurrent)
    )
    selectionHandler = onSelect
    render()
  }

  func handle(control: GamepadControl, isPressed: Bool) -> Bool {
    guard isPresented else { return false }
    guard isPressed else { return true }

    switch control {
    case .dpadUp, .dpadLeft:
      state.move(step: -1)
      render()
    case .dpadDown, .dpadRight:
      state.move(step: 1)
      render()
    case .a:
      let entry = entries[state.selectedIndex]
      let handler = selectionHandler
      dismiss()
      handler?(entry)
    case .b:
      dismiss()
    default:
      break
    }
    return true
  }

  func dismiss() {
    panel?.orderOut(nil)
    panel = nil
    entries = []
    selectionHandler = nil
  }

  private func render() {
    panel?.orderOut(nil)

    let width: CGFloat = 440
    let height = CGFloat(78 + entries.count * 36)
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true

    let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
    effect.autoresizingMask = [.width, .height]
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 16
    effect.layer?.masksToBounds = true

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(stack)

    let heading = NSTextField(labelWithString: "Codex 窗口 · \(entries.count)")
    heading.font = .systemFont(ofSize: 17, weight: .semibold)
    heading.textColor = .labelColor
    stack.addArrangedSubview(heading)

    for (index, entry) in entries.enumerated() {
      let selection = index == state.selectedIndex ? "▶" : " "
      let current = entry.isCurrent ? "●" : " "
      let row = NSTextField(
        labelWithString: "\(selection) \(current)  \(index + 1). \(entry.title)"
      )
      row.font = .monospacedSystemFont(
        ofSize: 14,
        weight: index == state.selectedIndex ? .bold : .regular
      )
      row.textColor = index == state.selectedIndex ? .selectedControlTextColor : .labelColor
      stack.addArrangedSubview(row)
    }

    let hint = NSTextField(labelWithString: "十字键选择   A 进入   B 取消")
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .secondaryLabelColor
    stack.addArrangedSubview(hint)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 22),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -22),
      stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -16),
    ])

    panel.contentView = effect
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    if let frame = screen?.visibleFrame {
      panel.setFrameOrigin(
        NSPoint(x: frame.midX - width / 2, y: frame.midY - height / 2)
      )
    }
    panel.orderFrontRegardless()
    self.panel = panel
  }
}

enum CodexProjectDeepLink {
  static func url(for folder: URL) -> URL? {
    guard folder.isFileURL, folder.path.hasPrefix("/") else { return nil }
    var components = URLComponents()
    components.scheme = "codex"
    components.host = "threads"
    components.path = "/new"
    components.queryItems = [URLQueryItem(name: "path", value: folder.path)]
    return components.url
  }
}
