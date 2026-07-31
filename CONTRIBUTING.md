# Contributing

Thanks for helping improve Xbox Codex Bridge. Small, testable changes are the easiest to review.

## Development setup

Requirements:

- macOS 13 or later
- Xcode Command Line Tools or Xcode
- Node.js 18 or later for the dashboard contract tests

Clone the repository, then run:

```bash
swift test
for test_file in Tests/*.js; do node "$test_file" || exit 1; done
swift build -c release
```

`Tests/AppBundleConfigTests.js` builds an ad-hoc-signed app and starts an ephemeral loopback server. macOS or a restricted sandbox may ask for permission to bind that local test port.

## Pull requests

1. Keep the change focused and explain the controller behavior it changes.
2. Add or update a regression test before changing behavior.
3. Update `README.md` when a default mapping, setup step, or limitation changes.
4. Report which controller model, connection type, macOS version, and Codex App version you tested.
5. Do not commit `.build`, app bundles, logs, Accessibility dumps, or screenshots containing private task content.

## Compatibility changes

Codex menu titles and Accessibility labels can change between app versions. Prefer exact, allow-listed controls and fail closed when a target cannot be verified. Do not add broad text matching or automatic approval behavior.
