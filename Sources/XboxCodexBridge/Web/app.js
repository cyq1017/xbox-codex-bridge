const layerLabels = {
  base: "BASE",
  task: "TASK · LB",
  developer: "DEV · RB",
  safety: "SAFE · LB+RB",
  system: "SYSTEM · VIEW",
};

const controlLabels = {
  a: "A Button", b: "B Button", x: "X Button", y: "Y Button",
  lb: "Left Bumper", rb: "Right Bumper", lt: "Left Trigger", rt: "Right Trigger",
  l3: "Left Stick Click", r3: "Right Stick Click",
  dpadUp: "D-pad Up", dpadRight: "D-pad Right", dpadDown: "D-pad Down", dpadLeft: "D-pad Left",
  leftStickUp: "Left Stick Up", leftStickRight: "Left Stick Right",
  leftStickDown: "Left Stick Down", leftStickLeft: "Left Stick Left",
  rightStickUp: "Right Stick Up", rightStickRight: "Right Stick Right",
  rightStickDown: "Right Stick Down", rightStickLeft: "Right Stick Left",
  menu: "Menu Button", view: "View Button", share: "Share Button", home: "Xbox Logo",
};

let actions = [];
let configuration = { layers: {} };
let selectedLayer = "base";
let selectedControl = "a";
let toastTimer;
let completionFlashTimer;
let observedCompletionSequence;
const fixedControls = new Set(["lb", "rb", "lt"]);
const reliableUIControls = new Set([
  "focusComposer", "clearComposer", "composerMoveLeft", "composerMoveRight",
  "composerMoveLineStart", "composerMoveLineEnd", "composerSelectLeft",
  "composerSelectRight", "composerSelectLineStart", "composerSelectLineEnd",
  "composerDeleteBackward", "selectionAddToTask", "selectionAskSideChat",
  "selectionMoreDetails", "previousWindow", "nextWindow", "newTaskWindow",
  "windowSwitcher", "launchCodex", "modelPicker", "permissionPicker",
  "reasoningIncrease", "reasoningDecrease",
  "reasoningCycle", "fastToggle", "planToggle",
]);

const actionSelect = document.querySelector("#action-select");
const shortcutNote = document.querySelector("#shortcut-note");

async function requestJSON(path, options = {}, didRefreshSession = false) {
  const response = await fetch(path, { ...options, credentials: "same-origin" });
  if (response.status === 403 && !didRefreshSession) {
    try {
      const refresh = await fetch("/", {
        cache: "no-store",
        credentials: "same-origin",
      });
      if (refresh.ok) return requestJSON(path, options, true);
    } catch {
      // Preserve the original authorization error when the local session cannot refresh.
    }
  }
  const contentType = response.headers.get("content-type") || "";
  const body = contentType.includes("application/json")
    ? await response.json()
    : { message: await response.text() };
  if (!response.ok) throw new Error(body.message || `Request failed: ${response.status}`);
  return body;
}

async function initialize() {
  try {
    [actions, configuration] = await Promise.all([
      requestJSON("/api/actions"),
      requestJSON("/api/config"),
    ]);
    buildActionSelect();
    buildShortcutList();
    bindEvents();
    selectControl("a");
    pollState();
    pollWindows();
  } catch (error) {
    showToast(error.message, true);
  }
}

function buildActionSelect() {
  actionSelect.replaceChildren();
  const none = document.createElement("option");
  none.value = "";
  none.textContent = "未分配";
  actionSelect.append(none);

  const categories = new Map();
  actions.forEach((action) => {
    if (!categories.has(action.category)) categories.set(action.category, []);
    categories.get(action.category).push(action);
  });
  categories.forEach((items, category) => {
    const group = document.createElement("optgroup");
    group.label = category;
    items.forEach((action) => {
      const option = document.createElement("option");
      option.value = action.id;
      option.textContent = action.label;
      group.append(option);
    });
    actionSelect.append(group);
  });
}

function buildShortcutList() {
  const list = document.querySelector("#shortcut-list");
  list.replaceChildren();
  actions.filter((action) => action.dispatch.requiresShortcutSetup).forEach((action) => {
    const row = document.createElement("div");
    row.className = "shortcut-item";
    const label = document.createElement("span");
    label.textContent = action.label;
    const key = document.createElement("kbd");
    key.textContent = formatShortcut(action.dispatch);
    row.append(label, key);
    list.append(row);
  });
}

function bindEvents() {
  document.querySelectorAll("[data-layer]").forEach((button) => {
    button.addEventListener("click", () => selectLayer(button.dataset.layer));
  });
  document.querySelectorAll("[data-control]").forEach((button) => {
    button.addEventListener("click", () => selectControl(button.dataset.control));
  });
  actionSelect.addEventListener("change", updateShortcutNote);
  document.querySelector("#save-mapping").addEventListener("click", saveMapping);
  document.querySelector("#test-action").addEventListener("click", testSelectedAction);
  document.querySelector("#test-haptic").addEventListener("click", () => postSimple("/api/haptic", {}));
  document.querySelectorAll("[data-light]").forEach((button) => {
    button.addEventListener("click", () => {
      const [red, green, blue] = button.dataset.light.split(",").map(Number);
      postSimple("/api/light", { red, green, blue });
    });
  });
  document.querySelector("#export-config").addEventListener("click", exportConfig);
  document.querySelector("#import-config").addEventListener("change", importConfig);
}

function selectLayer(layer) {
  selectedLayer = layer;
  document.querySelectorAll("[data-layer]").forEach((button) => {
    button.classList.toggle("active", button.dataset.layer === layer);
  });
  selectControl(selectedControl);
}

function selectControl(control) {
  selectedControl = control;
  document.querySelectorAll("[data-control]").forEach((button) => {
    button.classList.toggle("selected", button.dataset.control === control);
  });
  document.querySelector("#selected-control-badge").textContent = shortControlName(control);
  document.querySelector("#selected-control-name").textContent = controlLabels[control] || control;
  actionSelect.value = configuration.layers?.[selectedLayer]?.[control] || "";
  const isFixed = fixedControls.has(control);
  actionSelect.disabled = isFixed;
  document.querySelector("#save-mapping").disabled = isFixed;
  updateShortcutNote();
}

function shortControlName(control) {
  const compact = {
    dpadUp: "D↑", dpadRight: "D→", dpadDown: "D↓", dpadLeft: "D←",
    leftStickUp: "L↑", leftStickRight: "L→", leftStickDown: "L↓", leftStickLeft: "L←",
    rightStickUp: "R↑", rightStickRight: "R→", rightStickDown: "R↓", rightStickLeft: "R←",
  };
  return compact[control] || control.toUpperCase();
}

function updateShortcutNote() {
  const action = actions.find((item) => item.id === actionSelect.value);
  document.querySelector("#test-action").disabled =
    fixedControls.has(selectedControl) || !action?.isSafeForWebTest
      || !isReliableDispatch(action?.dispatch);
  if (fixedControls.has(selectedControl)) {
    shortcutNote.textContent = selectedControl === "lt"
      ? "LT 通过 macOS 辅助功能直接按 Codex 的听写按钮；等当前回复结束后，按住说话、松开停止，无需绑定快捷键。"
      : `${selectedControl.toUpperCase()} 是固定层修饰键，不支持重映射。`;
    return;
  }
  if (!action) {
    shortcutNote.textContent = "该控件在这一层不会触发动作。";
    return;
  }
  if (!isReliableDispatch(action.dispatch)) {
    shortcutNote.textContent = `高级保留动作，当前可靠版不默认启用。${formatDispatch(action.dispatch)}`;
  } else if (action.holdDuration) {
    shortcutNote.textContent = `安全动作：需要持续按住 ${action.holdDuration} 秒。`;
  } else if (!action.isSafeForWebTest) {
    shortcutNote.textContent = "此动作可能产生输入或外部效果，只能通过实体手柄触发。";
  } else {
    shortcutNote.textContent = `执行方式：${formatDispatch(action.dispatch)}`;
  }
}

function isReliableDispatch(dispatch) {
  return ["pushToTalk", "plainKey", "nativeMenu", "keystroke"].includes(dispatch?.kind)
    || (dispatch?.kind === "uiControl" && reliableUIControls.has(dispatch.uiControlID));
}

function formatShortcut(dispatch) {
  const names = { control: "⌃", option: "⌥", shift: "⇧", command: "⌘" };
  return `${dispatch.modifiers.map((item) => names[item] || item).join("")}${(dispatch.key || "").toUpperCase()}`;
}

function formatDispatch(dispatch) {
  switch (dispatch.kind) {
  case "pushToTalk":
    return "直接控制 Codex 听写";
  case "plainKey":
    return `按键：${(dispatch.key || "Key").toUpperCase()}`;
  case "keystroke":
    return `已验证快捷键：${formatShortcut(dispatch)}`;
  case "nativeMenu":
    return `原生菜单：${(dispatch.menuPath || []).join(" → ")}`;
  case "uiControl":
    return `${isReliableDispatch(dispatch) ? "辅助功能控件" : "未验证界面控件"}：${dispatch.uiControlID || "unknown"}`;
  case "shortcut":
    return `未验证快捷键：${formatShortcut(dispatch)}`;
  case "commandPalette":
    return `未验证命令菜单：${dispatch.commandTitle || "unknown"}`;
  case "unavailable":
    return `未接入：${dispatch.unavailableReason || "No verified adapter"}`;
  default:
    return `未知执行方式：${dispatch.kind || "unknown"}`;
  }
}

function windowButtonLabel(windowInfo) {
  return `${windowInfo.isFocused ? "当前 · " : ""}${windowInfo.title}`;
}

async function pollWindows() {
  try {
    renderWindows(await requestJSON("/api/windows"));
  } catch (error) {
    document.querySelector("#window-list").textContent = "窗口读取失败";
  }
  window.setTimeout(pollWindows, 2500);
}

function renderWindows(windows) {
  const list = document.querySelector("#window-list");
  document.querySelector("#window-count").textContent = String(windows.length);
  list.replaceChildren();
  if (!windows.length) {
    const empty = document.createElement("span");
    empty.className = "muted";
    empty.textContent = "没有可用的 Codex 主窗口";
    list.append(empty);
    return;
  }
  windows.forEach((windowInfo) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = windowInfo.isFocused ? "focused" : "";
    button.textContent = windowButtonLabel(windowInfo);
    button.addEventListener("click", async () => {
      await postSimple("/api/window", { id: windowInfo.id });
    });
    list.append(button);
  });
}

async function saveMapping() {
  if (fixedControls.has(selectedControl)) return;
  if (!configuration.layers[selectedLayer]) configuration.layers[selectedLayer] = {};
  if (actionSelect.value) configuration.layers[selectedLayer][selectedControl] = actionSelect.value;
  else delete configuration.layers[selectedLayer][selectedControl];
  try {
    const result = await requestJSON("/api/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(configuration),
    });
    showToast(result.message);
  } catch (error) {
    showToast(error.message, true);
  }
}

async function testSelectedAction() {
  const id = actionSelect.value;
  if (!id) return showToast("当前控件没有动作", true);
  await postSimple("/api/action", { id });
}

async function postSimple(path, body) {
  try {
    const result = await requestJSON(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    showToast(result.message);
    return result;
  } catch (error) {
    showToast(error.message, true);
  }
}

async function pollState() {
  try {
    const state = await requestJSON("/api/state");
    renderState(state);
  } catch (error) {
    document.querySelector("#last-message").textContent = "Helper 连接中断";
  }
  window.setTimeout(pollState, 100);
}

function renderState(state) {
  setStatus("controller-status", state.connected, state.connected ? "手柄已连接" : "等待手柄");
  setStatus("accessibility-status", state.capabilities.accessibility, "辅助功能");
  setStatus("haptic-status", state.capabilities.haptics, "震动");
  setStatus("light-status", state.capabilities.light, "灯光");
  document.querySelector("#controller-name").textContent = state.controllerName || "Xbox Wireless Controller";
  document.querySelector("#last-message").textContent = state.lastMessage;
  syncCompletionFlash(state.completionSequence);
  document.querySelector("#ptt-state").textContent = state.pushToTalkState.toUpperCase();
  document.querySelector("#live-layer").textContent = `LIVE · ${layerLabels[state.activeLayer] || state.activeLayer}`;
  document.querySelectorAll("[data-layer]").forEach((button) => {
    button.classList.toggle("live", button.dataset.layer === state.activeLayer);
  });
  const pressed = new Set(state.pressed);
  document.querySelectorAll("[data-control]").forEach((button) => {
    button.classList.toggle("pressed", pressed.has(button.dataset.control));
  });
  moveStick(".left-stick .stick-button", state.axes.leftX, state.axes.leftY);
  moveStick(".right-stick .stick-button", state.axes.rightX, state.axes.rightY);
}

function shouldFlashCompletion(previousSequence, nextSequence) {
  return Number.isInteger(previousSequence)
    && Number.isInteger(nextSequence)
    && nextSequence > previousSequence;
}

function syncCompletionFlash(nextSequence) {
  if (shouldFlashCompletion(observedCompletionSequence, nextSequence)) {
    triggerCompletionFlash();
  }
  observedCompletionSequence = nextSequence;
}

function triggerCompletionFlash() {
  const body = document.body;
  body.classList.remove("completion-flash");
  void body.offsetWidth;
  body.classList.add("completion-flash");
  window.clearTimeout(completionFlashTimer);
  completionFlashTimer = window.setTimeout(
    () => body.classList.remove("completion-flash"),
    1600,
  );
}

function setStatus(id, ready, label) {
  const element = document.querySelector(`#${id}`);
  element.classList.toggle("ready", ready);
  element.lastChild.textContent = label;
}

function moveStick(selector, x, y) {
  const stick = document.querySelector(selector);
  stick.style.marginLeft = `${x * 9}px`;
  stick.style.marginTop = `${-y * 9}px`;
}

function exportConfig() {
  const blob = new Blob([JSON.stringify(configuration, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "xbox-codex-mapping.json";
  anchor.click();
  URL.revokeObjectURL(url);
}

async function importConfig(event) {
  const [file] = event.target.files;
  if (!file) return;
  if (file.size > 1024 * 1024) return showToast("配置文件超过 1 MB", true);
  try {
    const candidate = JSON.parse(await file.text());
    const result = await requestJSON("/api/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(candidate),
    });
    configuration = candidate;
    selectControl(selectedControl);
    showToast(result.message);
  } catch (error) {
    showToast(`导入失败：${error.message}`, true);
  } finally {
    event.target.value = "";
  }
}

function showToast(message, isError = false) {
  const toast = document.querySelector("#toast");
  toast.textContent = message;
  toast.classList.toggle("error", isError);
  toast.classList.add("visible");
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove("visible"), 2800);
}

initialize();
