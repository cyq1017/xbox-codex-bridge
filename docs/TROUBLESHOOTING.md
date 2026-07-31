# 安装与排障

## 交给 Codex 诊断（推荐）

在已克隆的 Xbox Codex Bridge 项目中打开 Codex，粘贴下面的提示词：

```text
请诊断当前 Xbox Codex Bridge 为什么不能正常工作。

先阅读 README.md、docs/TROUBLESHOOTING.md 和相关脚本。只做只读检查：确认 Bridge/LaunchAgent 是否运行、127.0.0.1:8765 是否监听、手柄是否被识别、辅助功能状态、最近的本地日志，以及与故障最相关的测试。不要修改任何文件，不要使用 sudo，不要修改 Codex App，不要重置我的映射，不要关闭无关进程，也不要绕过 macOS 权限确认。最后告诉我：根因、证据、最小修复步骤，以及哪些步骤必须由我手动确认；需要修改或重装时先等我批准。
```

为了避免公开私人任务内容，提交 Issue 前请先检查日志和截图；不要上传访问令牌、用户名路径、辅助功能树全文或包含对话内容的截图。

## 安装发生了什么

运行 `./run.command` 后，项目会：

1. 构建 `.build/XboxCodexBridge.app`；
2. 安装到 `~/Applications/XboxCodexBridge.app`；
3. 安装当前用户的 LaunchAgent；
4. 请求该 App 的辅助功能权限；
5. 在 `127.0.0.1:8765` 启动控制台。

有 Apple Development 证书时脚本自动选择第一个可用证书；没有证书时使用 ad-hoc 签名。也可以指定：

```bash
XBOX_CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./run.command
```

## 控制台打不开

```bash
./run.command
launchctl print gui/$UID/io.github.cyq1017.xbox-codex-bridge
tail -n 80 ~/Library/Logs/XboxCodexBridge.error.log
```

如果端口被占用：

```bash
lsof -nP -iTCP:8765 -sTCP:LISTEN
```

不要同时运行源码目录里的临时二进制和已安装 App。

## Share 能唤醒，但其他按键无效

控制台能看到按键亮起，说明蓝牙/GameController 正常；Codex 没有响应通常表示辅助功能权限没有应用到当前安装的 App。

1. 在辅助功能中删除旧的 Xbox Codex Bridge 条目。
2. 运行 `./run.command`。
3. 重新启用 `~/Applications/XboxCodexBridge.app`。
4. 再运行一次 `./run.command`。

## LT 没有开始录音

- 等待当前 Codex 回复结束，确认输入框麦克风按钮可用。
- 确认授权对象不是 Terminal 或 `.build` 中的临时程序。
- 让新启动的 Codex 完整加载输入框后再按 LT。
- ad-hoc App 重新构建后，尝试关闭并重新开启辅助功能权限。

## 模型或权限菜单打开后无法选择

- 打开模型菜单后松开 RB，再用十字键与 A/B。
- 打开权限菜单后松开 LB/RB，再用十字键上/下、A 和 B。
- 如果全局侧边栏或底部面板仍被触发，按 B 退出菜单后重新打开。
- Codex 更新可能改变菜单结构；请在 Issue 中附上 Codex App 版本和控制台消息。

## View 窗口选择器无法进入

确保弹层确实显示后再按 A。跨显示器或 Space 的窗口由 Codex 原生 Window 菜单提供；已经关闭或正在显示听写浮层的窗口不会作为普通任务窗口进入。

## 没有震动或灯光

控制台只报告手柄和连接方式实际暴露的能力。很多 Xbox 手柄的 Logo 灯由系统管理，无法改色；蓝牙下的震动能力也可能不同于 USB。

- 普通 RT 发送不会产生完成震动。
- 使用 `RB + RT` 发送真实任务，并确认任务确实进入运行状态。
- 网页手动震动测试用于确认基础 haptic 能力。
- 权限震动要求安装 Hook，并且真实审批卡片仍在屏幕上。

## 卸载

保留本地映射：

```bash
./Scripts/uninstall-background-service.sh
```

同时删除配置和日志：

```bash
./Scripts/uninstall-background-service.sh --purge
```

卸载脚本只处理 Xbox Codex Bridge 自己的 App、LaunchAgent、日志和配置，不会修改 Codex App。
