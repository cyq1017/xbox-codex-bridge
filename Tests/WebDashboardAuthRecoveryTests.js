const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const appPath = path.join(
  __dirname,
  "..",
  "Sources",
  "XboxCodexBridge",
  "Web",
  "app.js",
);
const source = fs.readFileSync(appPath, "utf8").replace(/\ninitialize\(\);\s*$/, "");
const context = {
  document: { querySelector: () => ({}) },
  window: {},
};
vm.createContext(context);
vm.runInContext(source, context);

function response(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: {
      get: () => "application/json",
    },
    json: async () => body,
    text: async () => String(body.message || body),
  };
}

async function main() {
  const calls = [];
  context.fetch = async (path, options = {}) => {
    calls.push({ path, options });
    if (calls.length === 1) return response(403, { message: "Forbidden" });
    if (calls.length === 2) {
      assert.equal(path, "/", "a stale session should be refreshed from the local dashboard root");
      assert.equal(options.credentials, "same-origin");
      return response(200, { message: "Session refreshed" });
    }
    return response(200, { message: "Haptic played" });
  };

  const result = await vm.runInContext(
    `requestJSON("/api/haptic", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    })`,
    context,
  );

  assert.equal(result.message, "Haptic played");
  assert.equal(calls.length, 3);
  assert.equal(calls[2].path, "/api/haptic");
  assert.equal(calls[2].options.credentials, "same-origin");
  console.log("Web dashboard auth recovery passed");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
