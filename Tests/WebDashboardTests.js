const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const appPath = path.join(
  __dirname,
  "..",
  "Sources",
  "XboxCodexBridge",
  "Web",
  "app.js",
);
const stylesPath = path.join(
  __dirname,
  "..",
  "Sources",
  "XboxCodexBridge",
  "Web",
  "styles.css",
);
const source = fs.readFileSync(appPath, "utf8").replace(/\ninitialize\(\);\s*$/, "");
const styles = fs.readFileSync(stylesPath, "utf8");
const context = {
  document: { querySelector: () => ({}) },
  window: {},
};
vm.createContext(context);
vm.runInContext(source, context);

function format(dispatch) {
  return vm.runInContext(`formatDispatch(${JSON.stringify(dispatch)})`, context);
}

function isReliable(dispatch) {
  return vm.runInContext(`isReliableDispatch(${JSON.stringify(dispatch)})`, context);
}

assert.equal(
  format({ kind: "nativeMenu", menuPath: ["View", "Toggle Sidebar"] }),
  "原生菜单：View → Toggle Sidebar",
);
assert.equal(format({ kind: "plainKey", key: "return" }), "按键：RETURN");
assert.equal(
  format({ kind: "keystroke", key: "o", modifiers: ["command", "option"] }),
  "已验证快捷键：⌘⌥O",
);
assert.equal(format({ kind: "pushToTalk" }), "直接控制 Codex 听写");
assert.equal(
  format({ kind: "uiControl", uiControlID: "composerMoveLeft" }),
  "辅助功能控件：composerMoveLeft",
);
assert.equal(
  format({ kind: "shortcut", key: "p", modifiers: ["command", "option"] }),
  "未验证快捷键：⌘⌥P",
);
assert.equal(
  format({ kind: "commandPalette", commandTitle: "Skills" }),
  "未验证命令菜单：Skills",
);
assert.equal(
  format({ kind: "unavailable", unavailableReason: "No verified adapter" }),
  "未接入：No verified adapter",
);
assert.equal(isReliable({ kind: "nativeMenu" }), true);
assert.equal(isReliable({ kind: "plainKey" }), true);
assert.equal(isReliable({ kind: "keystroke" }), true);
assert.equal(isReliable({ kind: "pushToTalk" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "focusComposer" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "composerDeleteBackward" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "selectionAddToTask" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "previousWindow" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "newTaskWindow" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "windowSwitcher" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "launchCodex" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "modelPicker" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "permissionPicker" }), true);
assert.equal(isReliable({ kind: "uiControl", uiControlID: "newProject" }), false);
assert.equal(isReliable({ kind: "commandPalette" }), false);
assert.equal(
  vm.runInContext(
    `windowButtonLabel(${JSON.stringify({ title: "用Xbox手柄复刻Micro功能", isFocused: true })})`,
    context,
  ),
  "当前 · 用Xbox手柄复刻Micro功能",
);
assert.equal(vm.runInContext("shouldFlashCompletion(undefined, 1)", context), false);
assert.equal(vm.runInContext("shouldFlashCompletion(1, 1)", context), false);
assert.equal(vm.runInContext("shouldFlashCompletion(1, 2)", context), true);
assert.equal(vm.runInContext("shouldFlashCompletion(4, 0)", context), false);
assert.match(styles, /body\.completion-flash::after/);
assert.match(styles, /body\.completion-flash \.xbox-light/);

console.log("Web dashboard dispatch formatting passed");
