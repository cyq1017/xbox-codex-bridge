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
  "VERSION",
  "CONTRIBUTING.md",
  "SECURITY.md",
  ".github/workflows/ci.yml",
  ".github/release.yml",
  "Scripts/uninstall-background-service.sh",
  "Scripts/release-check.sh",
  "LaunchAgent/io.github.cyq1017.xbox-codex-bridge.plist",
  "docs/CONTROLS.md",
  "docs/TROUBLESHOOTING.md",
  "docs/releases/v0.1.0.md",
  "docs/releases/v0.1.0-smoke-test.md",
  "assets/xbox-codex-bridge-hero.png",
]) {
  assertExists(relativePath);
}

assert.equal(read("VERSION").trim(), "0.1.0");

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

const releaseCheck = read("Scripts/release-check.sh");
assert.match(releaseCheck, /swift test/);
assert.match(releaseCheck, /Tests\/\*\.js/);
assert.match(releaseCheck, /swift build -c release/);
assert.match(releaseCheck, /XboxLightProbe/);
assert.match(releaseCheck, /git diff --check/);
assert.match(
  releaseCheck,
  /exclude\)Scripts\/release-check\.sh/,
  "the private-data scan should exclude its own detection patterns",
);

assert.doesNotMatch(
  read("docs/releases/v0.1.0-smoke-test.md"),
  /\/Users\//,
  "public validation docs should not include a maintainer-specific path",
);

const readme = read("README.md");
assert.match(readme, /RB \+ RT/);
assert.match(readme, /发送并在任务完成后震动提醒/);
assert.match(readme, /MIT License/);
assert.match(readme, /assets\/xbox-codex-bridge-hero\.png/);
assert.match(readme, /docs\/CONTROLS\.md/);
assert.match(readme, /docs\/TROUBLESHOOTING\.md/);
assert.ok(
  readme.split("\n").length <= 190,
  "README should stay concise; detailed guidance belongs in docs",
);

console.log("Open-source release contract passed");
