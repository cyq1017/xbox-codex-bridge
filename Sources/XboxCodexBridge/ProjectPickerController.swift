import AppKit
import Foundation

final class ProjectPickerController {
  private var panel: NSOpenPanel?

  func chooseFolder(completion: @escaping (URL?) -> Void) {
    guard panel == nil else { return }
    let panel = NSOpenPanel()
    panel.title = "创建或打开独立 Codex 项目"
    panel.message = "选择已有文件夹，或在任意位置新建一个文件夹。"
    panel.prompt = "在 Codex 中打开"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.treatsFilePackagesAsDirectories = true

    self.panel = panel
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self] response in
      let selected = response == .OK ? panel.url : nil
      self?.panel = nil
      completion(selected)
    }
  }
}
