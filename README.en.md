# Xbox Codex Bridge

[中文说明](README.md) · [MIT License](LICENSE)

Xbox Codex Bridge is a local macOS helper and browser-based console that maps an Xbox controller to a Codex control surface inspired by the core interaction ideas of Codex Micro.

It supports push-to-talk dictation, send/cancel, model and permission menus, task and window navigation, composer editing, optional approval alerts, and opt-in task-completion haptics. It is a community experiment, not an OpenAI product or a one-to-one Codex Micro clone.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools or Xcode
- Codex desktop app (`com.openai.codex`)
- Xbox Wireless Controller or a compatible extended gamepad

## Quick start

```bash
git clone https://github.com/cyq1017/xbox-codex-bridge.git
cd xbox-codex-bridge
./run.command
```

Enable **Xbox Codex Bridge** under **System Settings → Privacy & Security → Accessibility**, then run `./run.command` again. The local dashboard is available at `http://127.0.0.1:8765/`.

The packaging script uses the first available Apple Development identity. If none exists, it falls back to ad-hoc signing. You can specify an identity explicitly:

```bash
XBOX_CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./run.command
```

## Core controls

| Gesture | Action |
| --- | --- |
| Share | Launch or focus Codex |
| Hold/release LT | Start/stop dictation |
| Tap RT | Send |
| Hold RT | Insert a newline |
| B | Stop the current task or close an overlay |
| Y | Create a task |
| Tap View | Show the global Codex window picker |
| RB + A | Open the model/reasoning picker |
| RB + RT | Send and notify on completion |
| LB + RB + Y | Open the native permission-mode menu |
| View + X | Create a standalone task |
| View + Y | Start a project task through Open Folder |

The Chinese README contains the complete mapping table, haptic behavior, troubleshooting guide, security boundaries, and known limitations.

## Uninstall

```bash
./Scripts/uninstall-background-service.sh
```

Add `--purge` to remove local mappings and logs as well.

## Development

```bash
swift test
for test_file in Tests/*.js; do node "$test_file" || exit 1; done
swift build -c release
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before submitting changes or vulnerability reports.

## License and trademarks

Released under the [MIT License](LICENSE). Codex, OpenAI, Xbox, and related marks belong to their respective owners. This project is not affiliated with or endorsed by OpenAI or Microsoft.
