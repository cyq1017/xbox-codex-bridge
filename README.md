# Xbox Codex Bridge

[English](README.en.md) · [MIT License](LICENSE)

[![CI](https://github.com/cyq1017/xbox-codex-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/cyq1017/xbox-codex-bridge/actions/workflows/ci.yml)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

用 Xbox 手柄复刻 Codex Micro 的核心交互体验：按住说话、发送与中止任务、切换窗口、选择模型和权限，并在需要你回来处理时通过手柄震动提醒。

> [!IMPORTANT]
> 这是一个社区制作的本地映射实验，不是 OpenAI 官方产品，也不是 Codex Micro 的一比一复制。它不会修改 Codex App，所有控制都通过 macOS GameController 与辅助功能完成。

## 能做什么

- **语音输入：**按住 LT 说话，松开后把识别结果写入 Codex 输入框；双击 LT 可锁定录音，再按一次停止。
- **高频任务控制：**RT 发送，长按 RT 换行，B 中止任务，Y 新建任务。
- **模型与权限：**通过手柄进入 Codex 原生模型、推理强度和权限菜单，并在菜单内完成选择。
- **窗口与文本编辑：**切换 Codex 窗口，移动光标，连续扩展选区，删除选中文字或清空输入框。
- **按需震动：**普通 RT 发送保持安静；`RB + RT` 发送并在任务完成后震动提醒。真实人工审批出现时也可以震动。
- **本地控制台：**在 `http://127.0.0.1:8765/` 查看手柄状态、键位和设备能力。

## 使用要求

- macOS 13 或更高版本
- Xcode Command Line Tools 或 Xcode（需要 Swift）
- Codex 桌面 App（bundle id：`com.openai.codex`）
- Xbox Wireless Controller 或兼容的 extended gamepad
- 蓝牙或 USB 连接均可；具体震动和灯光能力取决于控制器型号与连接方式

## 五分钟安装

### 1. 下载并启动

```bash
git clone https://github.com/cyq1017/xbox-codex-bridge.git
cd xbox-codex-bridge
./run.command
```

脚本会：

1. 构建 `XboxCodexBridge.app`；
2. 安装到 `~/Applications/XboxCodexBridge.app`；
3. 安装当前用户的 LaunchAgent，使 Bridge 登录后自动运行；
4. 打开 macOS 的辅助功能授权界面。

如果电脑上有 Apple Development 证书，脚本会自动使用第一个可用证书；没有证书时会使用 ad-hoc 签名。也可以手动指定：

```bash
XBOX_CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./run.command
```

ad-hoc 签名可以正常体验，但重新构建后 macOS 可能要求再次确认辅助功能权限。发布者签名并公证的 Release App 才适合长期免编译安装。

### 2. 开启辅助功能

打开：

**系统设置 → 隐私与安全性 → 辅助功能 → Xbox Codex Bridge**

请授权安装在 `~/Applications` 中的 **Xbox Codex Bridge**，不要授权旧的终端进程或 `.build` 目录中的临时可执行文件。授权后再运行一次：

```bash
./run.command
```

### 3. 连接并检查手柄

1. 通过蓝牙或 USB 连接 Xbox 手柄。
2. 打开 `http://127.0.0.1:8765/`。
3. 确认顶部显示“手柄已连接”和“辅助功能”。
4. 先在空白 Codex 输入框中测试 LT、RT 和 B。

## 默认键位

### 基础层

| 操作 | 功能 |
| --- | --- |
| Share | 启动或聚焦 Codex（推荐的一键唤醒键） |
| Xbox Logo | 尝试启动或聚焦 Codex；可能被 macOS 或游戏工具占用 |
| LT 按住/松开 | 开始/停止语音输入 |
| LT 双击 | 锁定录音；再按一次停止 |
| RT 单击 | 发送输入框内容 |
| RT 长按 | 插入换行 |
| B | 中止当前任务或关闭当前弹层 |
| X / 十字键下 | 打开或关闭底部面板 |
| Y | 新建任务 |
| MENU / 十字键上 | 打开或关闭侧边栏 |
| A | 打开或关闭侧面板 |
| 十字键左/右 | 上一个/下一个任务 |
| 左摇杆 | 连续移动光标；上/下到当前行首/行尾 |
| 右摇杆 | 连续扩展选区；上/下选到当前行首/行尾 |
| L3 | 删除选区；没有选区时删除前一个完整字符 |
| R3 单击/长按 | 聚焦输入框/清空当前输入框 |

### 任务层（按住 LB）

先用鼠标或触控板选中 Codex 输出文字，让原生浮动工具栏出现：

| 操作 | 功能 |
| --- | --- |
| LB + A | 添加到任务 |
| LB + X | 在侧边聊天中提问 |
| LB + Y | 更多详情 |
| LB + 十字键左/右 | 切换任务 |
| LB + 十字键上 | 置顶或取消置顶 |
| LB + RT | 新建任务 |

### 开发层（按住 RB）

| 操作 | 功能 |
| --- | --- |
| RB + A | 打开模型与推理强度菜单 |
| RB + RT | 发送并在任务完成后震动提醒 |
| RB + X | 切换 Fast 模式 |
| RB + Y | 切换 Plan 模式 |
| RB + B | 打开终端 |
| RB + 十字键下 | 打开或关闭底部面板 |
| RB + L3 | 打开文件夹 |

进入模型菜单后，用十字键移动，A 进入或确认，B 返回，十字键左/右用于多级菜单。菜单打开期间，这些按键会被菜单独占，不会触发全局侧边栏或底部面板动作。

### 安全层（同时按住 LB + RB）

| 操作 | 功能 |
| --- | --- |
| LB + RB + Y | 打开 Codex 原生权限模式菜单 |
| A 长按 | 确认真实审批卡片 |
| B 长按 | 拒绝真实审批卡片 |

权限菜单打开后松开 LB/RB，使用十字键上/下选择，A 确认，B 或十字键左取消。选择 Full access 后，Codex 自己的二次确认仍然保留，Bridge 不会自动批准。

### 窗口与系统层

| 操作 | 功能 |
| --- | --- |
| View 单击 | 显示所有 Codex 窗口；十字键选择，A 进入，B 取消 |
| View + X | 新建不继承当前项目的独立任务 |
| View + Y | 打开 Codex 原生“打开文件夹”流程，新建项目任务 |
| View + 十字键左/右 | 跨显示器与 Space 切换 Codex 窗口 |
| View + A | 设置 |
| View + B | 键盘快捷键 |

## 任务完成与审批震动

### 任务完成提醒

只有使用 `RB + RT` 发送的任务才会进入完成跟踪：

1. Bridge 发送输入内容；
2. 确认 Codex 确实进入运行状态；
3. 等待运行按钮消失并连续处于稳定空闲状态；
4. 手柄震动两次，同时网页 HUD 闪烁。

普通 RT 发送不会震动，因此日常短对话不会不断打扰你。这个流程不依赖 Codex 的 `Stop` Hook。

### 审批提醒（可选）

项目中的 [`Hooks/codex-haptics-hooks.json`](Hooks/codex-haptics-hooks.json) 提供 `PermissionRequest` Hook 示例。把该条目**合并**到 `~/.codex/hooks.json`，不要覆盖已有 Hook；重启 Codex，并在 Codex 提示时检查、信任该命令。

Hook 只通知 Bridge 开始检查。只有同一 Codex 窗口中真的存在可点击的允许和拒绝按钮时，Bridge 才会震动三次；自动审批不会触发提醒。

## 卸载

保留本地键位配置：

```bash
./Scripts/uninstall-background-service.sh
```

同时删除本地配置和日志：

```bash
./Scripts/uninstall-background-service.sh --purge
```

卸载脚本只处理 Xbox Codex Bridge 自己的 App、LaunchAgent、日志和配置，不会修改 Codex App。

## 常见问题

### `127.0.0.1:8765` 打不开

重新运行 `./run.command`，然后检查：

```bash
launchctl print gui/$UID/io.github.cyq1017.xbox-codex-bridge
tail -n 80 ~/Library/Logs/XboxCodexBridge.error.log
```

### LT 没有开始录音

- 确认授权对象是 `~/Applications/XboxCodexBridge.app`。
- 等待当前 Codex 回复结束，确保输入框的麦克风按钮可用。
- 让 Codex 至少完整启动一次，再测试 LT。
- 如果刚重新构建过 ad-hoc App，关闭并重新开启辅助功能权限。

### Share 可以唤醒，但其他按键无效

通常是辅助功能权限尚未应用到当前安装的 App。检查控制台是否能看到按键亮起，再重新授权 `Xbox Codex Bridge` 并运行一次 `./run.command`。

### 没有震动或灯光

Apple GameController 只会暴露控制器与连接方式实际支持的能力。很多 Xbox 手柄的 Logo 灯由系统管理，无法改色；蓝牙下也可能只提供有限震动能力。控制台会诚实显示当前能力，不支持时不会假装执行成功。

## 安全与隐私

- HTTP 服务只绑定 `127.0.0.1`。
- 会改变状态的网页请求需要精确 Origin、JSON content type 和随机 SameSite Cookie。
- 映射只接受已知层、控制器输入和动作。
- 网页不能测试发送、审批、Git/PR 等有副作用的动作；这些动作需要实体手柄。
- Bridge 不上传语音、任务内容或映射，也不修改 Codex App 文件。

更完整的报告方式见 [SECURITY.md](SECURITY.md)。

## 已知限制

- Codex Micro 的原生按键事件没有公开接口；LT 通过 macOS 辅助功能复现输入框中的可见效果。
- Codex 更新可能改变菜单标题或辅助功能结构，需要同步适配。
- 后台窗口切换和 Xbox Logo 键会受到 macOS、显示器 Space 与第三方游戏软件影响。
- 手柄灯光与震动能力因型号、固件和蓝牙/USB 连接方式不同而不同。
- 当前源码安装使用本地签名；正式免编译分发仍需要 Developer ID 签名与 Apple 公证。

## 开发与测试

```bash
swift test
for test_file in Tests/*.js; do node "$test_file" || exit 1; done
swift build -c release
```

项目结构：

```text
Sources/XboxCodexBridgeCore/   映射、状态机和请求验证
Sources/XboxCodexBridge/       GameController、辅助功能、本地服务
Sources/XboxCodexBridge/Web/   映射控制台
Tests/                         Swift 与 Node 契约测试
Hooks/                         可选 Codex Hook 示例
Scripts/                       打包、安装与卸载
```

欢迎提交问题和改进，提交前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 项目定位

Xbox Codex Bridge 的目标不是复制一块官方硬件，而是验证一个想法：把语音、任务、模型、权限、窗口和触觉反馈组织成一套可以肌肉记忆的 Codex 实体控制界面。

## License

Xbox Codex Bridge 使用 [MIT License](LICENSE)。Codex、OpenAI、Xbox 和相关商标归各自权利人所有；本项目与 OpenAI 或 Microsoft 没有隶属或官方合作关系。
