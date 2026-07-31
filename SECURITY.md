# Security Policy

Xbox Codex Bridge controls a local desktop application through macOS Accessibility. Treat changes to HTTP routes, Accessibility matching, approval handling, hooks, and command dispatch as security-sensitive.

## Reporting a vulnerability

Please use the repository's **GitHub Security Advisories → Report a vulnerability** flow. Do not include working exploits, private Codex task content, credentials, or Accessibility dumps in a public issue.

Include the affected commit or release, macOS version, Codex App version, controller connection type, reproduction steps, and the smallest safe diagnostic output.

## Security boundaries

- The web server must remain bound to `127.0.0.1`.
- State-changing web requests must retain Origin, content-type, cookie, and allow-list validation.
- Approval actions must require an explicit physical hold and must never be automatically confirmed.
- Hook routes must stay fixed, loopback-only, and unable to edit mappings or invoke arbitrary actions.
- The project must not patch or redistribute Codex App files.

Security fixes are supported for the latest release only while the project is in MVP status.
