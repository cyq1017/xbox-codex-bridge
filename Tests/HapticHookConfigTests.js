const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const hookPath = path.join(__dirname, "..", "Hooks", "codex-haptics-hooks.json");
const config = JSON.parse(fs.readFileSync(hookPath, "utf8"));

assert.deepEqual(Object.keys(config.hooks).sort(), ["PermissionRequest"]);

const commands = Object.values(config.hooks)
  .flat()
  .flatMap((group) => group.hooks)
  .map((hook) => hook.command);

const handlers = Object.values(config.hooks)
  .flat()
  .flatMap((group) => group.hooks);

assert.equal(commands.length, 1);
assert(handlers.every((hook) => hook.type === "command" && hook.timeout === 2));
assert(commands.every((command) => command.includes("/usr/bin/curl")));
assert(commands.every((command) => command.includes("--max-time 1")));
assert(commands.every((command) => command.includes("X-Xbox-Codex-Hook: 1")));
assert(commands.every((command) => command.includes("Content-Type: application/json")));
assert(commands.every((command) => command.includes("http://127.0.0.1:8765/api/hooks/")));
assert(commands.every((command) => command.endsWith("|| true")));
assert(commands.some((command) => command.includes("/permission-request")));
assert(!commands.some((command) => command.includes("/turn-stopped")));

for (const command of commands) {
  const urls = command.match(/https?:\/\/[^ ']+/g) ?? [];
  assert(urls.length === 1);
  assert(urls[0].startsWith("http://127.0.0.1:8765/"));
}

console.log("Codex haptic hook config passed");
