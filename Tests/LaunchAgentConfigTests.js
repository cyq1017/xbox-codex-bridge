const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const launchAgentPath = path.join(
  projectRoot,
  "LaunchAgent",
  "io.github.cyq1017.xbox-codex-bridge.plist",
);
const installedAppPath = "@HOME@/Applications/XboxCodexBridge.app";
const appExecutablePath = `${installedAppPath}/Contents/MacOS/XboxCodexBridge`;

assert.ok(
  fs.existsSync(launchAgentPath),
  "LaunchAgent configuration should exist",
);

const configuration = JSON.parse(
  execFileSync(
    "/usr/bin/plutil",
    ["-convert", "json", "-o", "-", launchAgentPath],
    { encoding: "utf8" },
  ),
);

assert.equal(configuration.Label, "io.github.cyq1017.xbox-codex-bridge");
assert.deepEqual(configuration.ProgramArguments, [
  appExecutablePath,
  "--no-open",
  "--no-permission-prompt",
]);
assert.ok(
  !configuration.ProgramArguments.some(
    (argument) => argument.includes("/.build/") || argument.includes("swift"),
  ),
  "the LaunchAgent must not run the mutable SwiftPM build output",
);
assert.equal(
  configuration.WorkingDirectory,
  "@HOME@/Library/Application Support/XboxCodexBridge",
);
assert.ok(
  !configuration.WorkingDirectory.includes("/.build/"),
  "the LaunchAgent working directory must be independent of the source checkout",
);
assert.equal(configuration.RunAtLoad, true);
assert.deepEqual(configuration.KeepAlive, { SuccessfulExit: false });
assert.equal(configuration.LimitLoadToSessionType, "Aqua");
assert.equal(configuration.ProcessType, "Interactive");
assert.equal(configuration.ThrottleInterval, 5);
assert.equal(
  configuration.StandardOutPath,
  "@HOME@/Library/Logs/XboxCodexBridge.log",
);
assert.equal(
  configuration.StandardErrorPath,
  "@HOME@/Library/Logs/XboxCodexBridge.error.log",
);

console.log("Xbox Codex Bridge LaunchAgent config passed");
