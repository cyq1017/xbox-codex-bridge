#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

print "[1/7] Shell and plist validation"
zsh -n run.command Scripts/*.sh
/usr/bin/plutil -lint \
  App/Info.plist \
  LaunchAgent/io.github.cyq1017.xbox-codex-bridge.plist >/dev/null

print "[2/7] Swift test suite"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-/private/tmp/xboxcodexbridge-swift-module-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/xboxcodexbridge-clang-module-cache}"
swift test

print "[3/7] Dashboard, hook, packaging, and release contracts"
for test_file in Tests/*.js; do
  node "$test_file"
done

print "[4/7] Release build"
swift build -c release

print "[5/7] Isolated Xbox light probe tests (no hardware access)"
make -C Tools/XboxLightProbe test

print "[6/7] Repository hygiene"
git diff --check
git diff --cached --check
if git grep -n -I -E \
  '(BEGIN [A-Z ]*PRIVATE KEY|/Users/[^/]+|sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,})' \
  -- . \
  ':(exclude)Scripts/release-check.sh' \
  ':(exclude)Tests/OpenSourceReleaseTests.js'
then
  print -u2 "Potential private data found in tracked files."
  exit 1
fi

for ignored_path in .build docs/.DS_Store Tools/XboxLightProbe/build/xbox-light-probe; do
  git check-ignore -q "$ignored_path"
done

print "[7/7] Version consistency"
version="$(<VERSION)"
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
[[ "$version" == "$plist_version" ]]
rg -q "## ${version} - [0-9]{4}-[0-9]{2}-[0-9]{2}" CHANGELOG.md

print "AUTOMATED RELEASE CHECK PASSED (v$version)"
print "Optional compatibility check: docs/releases/v${version}-smoke-test.md"
