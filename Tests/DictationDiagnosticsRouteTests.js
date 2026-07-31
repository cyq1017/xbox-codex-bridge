const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const serverSource = fs.readFileSync(
  path.join(projectRoot, "Sources", "XboxCodexBridge", "LocalHTTPServer.swift"),
  "utf8",
);
const runtimeSource = fs.readFileSync(
  path.join(projectRoot, "Sources", "XboxCodexBridge", "BridgeRuntime.swift"),
  "utf8",
);

assert.match(
  serverSource,
  /case \("GET", "\/api\/diagnostics\/dictation"\):\s*guard hasValidCookie\(request\) else \{ return \.text\(403, "Forbidden"\) \}\s*return json\(runtime\.dictationDiagnostics\(\)\)/,
  "dictation diagnostics should be cookie-protected and read from the live runtime",
);
assert.match(
  runtimeSource,
  /func dictationDiagnostics\(\) -> CodexDictationDiagnostics\s*\{\s*dictationController\.diagnostics\(\)\s*\}/,
  "the runtime should delegate diagnostics to its active dictation controller",
);

console.log("Dictation diagnostics route contract passed");
