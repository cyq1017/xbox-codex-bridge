const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const serverSource = fs.readFileSync(
  path.join(projectRoot, "Sources", "XboxCodexBridge", "LocalHTTPServer.swift"),
  "utf8",
);

assert.match(
  serverSource,
  /case \("GET", "\/api\/state"\):\s*var response = json\(runtime\.currentSnapshot\(\)\)\s*if !hasValidCookie\(request\) \{\s*response\.headers\["Set-Cookie"\] = "bridge_token=.*; HttpOnly; SameSite=Strict; Path=\/"\s*\}\s*return response/,
  "a stale dashboard state poll should receive the current session cookie",
);

assert.match(
  serverSource,
  /private func isAuthorized\(_ request: HTTPRequest\) -> Bool \{\s*guard request\.headers\["origin"\] == origin,\s*request\.headers\["content-type"\]\?\.lowercased\(\)\.hasPrefix\("application\/json"\) == true,\s*hasValidCookie\(request\)/,
  "session recovery must preserve the Origin, JSON, and cookie checks for every mutation",
);

console.log("Session recovery route contract passed");
