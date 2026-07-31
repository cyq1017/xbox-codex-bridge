const assert = require("node:assert/strict");
const { execFileSync, spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const packageScriptPath = path.join(projectRoot, "Scripts", "package-app.sh");
const installScriptPath = path.join(projectRoot, "Scripts", "install-background-service.sh");
const appPath = path.join(projectRoot, ".build", "XboxCodexBridge.app");
const infoPlistPath = path.join(appPath, "Contents", "Info.plist");
const executablePath = path.join(appPath, "Contents", "MacOS", "XboxCodexBridge");
const webRoot = path.join(appPath, "Contents", "Resources", "Web");

assert.ok(
  fs.existsSync(packageScriptPath),
  "package-app.sh should build the fixed-identity app bundle",
);
assert.ok(
  fs.existsSync(installScriptPath),
  "install-background-service.sh should install the persistent service",
);

const installScript = fs.readFileSync(installScriptPath, "utf8");
const permissionSetup = "/usr/bin/open -n -W -g \"$app_destination\" --args --request-accessibility";
assert.ok(
  installScript.includes(permissionSetup),
  "installation should force a one-time App launch for Accessibility consent",
);
assert.ok(
  installScript.indexOf(permissionSetup) < installScript.indexOf("/bin/launchctl bootstrap"),
  "Accessibility consent setup should happen before the background service starts",
);

execFileSync(packageScriptPath, [], {
  cwd: projectRoot,
  stdio: "inherit",
  env: {
    ...process.env,
    XBOX_CODE_SIGN_IDENTITY: "-",
    XBOX_BUNDLE_IDENTIFIER: "io.github.cyq1017.xbox-codex-bridge",
  },
});

assert.ok(fs.statSync(appPath).isDirectory(), "the packaged .app should exist");
assert.ok(fs.existsSync(infoPlistPath), "the app should include Info.plist");
assert.ok(fs.statSync(executablePath).isFile(), "the app should include its executable");
assert.ok(
  (fs.statSync(executablePath).mode & 0o111) !== 0,
  "the app executable should be runnable",
);

const info = JSON.parse(
  execFileSync("/usr/bin/plutil", ["-convert", "json", "-o", "-", infoPlistPath], {
    encoding: "utf8",
  }),
);

assert.equal(info.CFBundleIdentifier, "io.github.cyq1017.xbox-codex-bridge");
assert.equal(info.CFBundleExecutable, "XboxCodexBridge");
assert.equal(info.CFBundlePackageType, "APPL");
assert.equal(info.CFBundleShortVersionString, "0.1.0");
assert.equal(info.LSUIElement, true);

for (const fileName of ["index.html", "app.js", "styles.css"]) {
  assert.ok(
    fs.existsSync(path.join(webRoot, fileName)),
    `the packaged app should include Web/${fileName}`,
  );
}

const signing = spawnSync(
  "/usr/bin/codesign",
  ["-d", "-r-", appPath],
  { encoding: "utf8" },
);
assert.equal(signing.status, 0, signing.stderr);
const signingInfo = `${signing.stdout}\n${signing.stderr}`;
assert.match(
  signingInfo,
  /designated => (?:identifier "io\.github\.cyq1017\.xbox-codex-bridge"|cdhash)/,
  "the app should carry a valid designated requirement for its signing mode",
);

function waitForReady(child) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error("packaged app did not report READY within 8 seconds"));
    }, 8_000);

    child.stdout.on("data", (chunk) => {
      if (chunk.toString().includes("READY http://127.0.0.1:")) {
        clearTimeout(timeout);
        resolve();
      }
    });
    child.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.once("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`packaged app exited before READY (code ${code})`));
    });
  });
}

function requestBody(port) {
  return new Promise((resolve, reject) => {
    http
      .get(`http://127.0.0.1:${port}/`, (response) => {
        let body = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          body += chunk;
        });
        response.on("end", () => {
          resolve({ statusCode: response.statusCode, body });
        });
      })
      .on("error", reject);
  });
}

async function main() {
  const port = 18765;
  const child = spawn(
    executablePath,
    ["--ephemeral", "--no-open", "--no-permission-prompt", "--port", String(port)],
    { stdio: ["ignore", "pipe", "pipe"] },
  );

  try {
    await waitForReady(child);
    const response = await requestBody(port);
    assert.equal(response.statusCode, 200);
    assert.match(response.body, /Xbox Codex Bridge/);
  } finally {
    if (!child.killed) {
      child.kill("SIGTERM");
    }
  }

  console.log("Xbox Codex Bridge app bundle config passed");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
