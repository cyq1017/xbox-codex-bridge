const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(projectRoot, relativePath), "utf8");
}

function assertExists(relativePath) {
  assert.ok(
    fs.existsSync(path.join(projectRoot, relativePath)),
    `${relativePath} should exist for the public release`,
  );
}

for (const relativePath of [
  ".gitignore",
  "LICENSE",
  "CONTRIBUTING.md",
  "SECURITY.md",
  ".github/workflows/ci.yml",
  "Scripts/uninstall-background-service.sh",
  "LaunchAgent/io.github.cyq1017.xbox-codex-bridge.plist",
]) {
  assertExists(relativePath);
}

const gitignore = read(".gitignore");
for (const ignored of [".build/", ".DS_Store", "Tools/XboxLightProbe/build/"]) {
  assert.ok(gitignore.includes(ignored), `.gitignore should exclude ${ignored}`);
}

const license = read("LICENSE");
assert.match(license, /MIT License/);
assert.match(license, /Copyright \(c\) 2026 cyq1017/);

const publicFiles = [
  "App/Info.plist",
  "Scripts/install-background-service.sh",
  "Scripts/package-app.sh",
  "Scripts/uninstall-background-service.sh",
  "LaunchAgent/io.github.cyq1017.xbox-codex-bridge.plist",
].map(read).join("\n");

assert.doesNotMatch(publicFiles, /@icloud\.com|Apple Development: .* \([A-Z0-9]{10}\)/);
assert.match(publicFiles, /io\.github\.cyq1017\.xbox-codex-bridge/);
assert.doesNotMatch(read("App/Info.plist"), /com\.caoyuqi/);
assert.doesNotMatch(
  read("LaunchAgent/io.github.cyq1017.xbox-codex-bridge.plist"),
  /com\.caoyuqi/,
);
assert.match(
  read("Scripts/install-background-service.sh"),
  /legacy_label="com\.caoyuqi\.xbox-codex-bridge"/,
  "the installer should remove the pre-release LaunchAgent during migration",
);

const packageScript = read("Scripts/package-app.sh");
assert.match(packageScript, /XBOX_CODE_SIGN_IDENTITY/);
assert.match(packageScript, /signing_identity="-"/);

const uninstallScript = read("Scripts/uninstall-background-service.sh");
assert.match(uninstallScript, /--purge/);
assert.match(uninstallScript, /Library\/LaunchAgents/);
assert.match(uninstallScript, /Applications\/XboxCodexBridge\.app/);

const workflow = read(".github/workflows/ci.yml");
assert.match(workflow, /swift test/);
assert.match(workflow, /Tests\/\*\.js/);

const readme = read("README.md");
assert.match(readme, /RB \+ RT/);
assert.match(readme, /发送并在任务完成后震动提醒/);
assert.match(readme, /MIT License/);

console.log("Open-source release contract passed");
