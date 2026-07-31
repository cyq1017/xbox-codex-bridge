#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="$project_root/.build/XboxCodexBridge.app"
release_path="$project_root/.build/release"
bundle_id="${XBOX_BUNDLE_IDENTIFIER:-io.github.cyq1017.xbox-codex-bridge}"
signing_identity="${XBOX_CODE_SIGN_IDENTITY:-}"
swift_module_cache="${SWIFT_MODULECACHE_PATH:-/private/tmp/xboxcodexbridge-swift-module-cache}"
clang_module_cache="${CLANG_MODULE_CACHE_PATH:-/private/tmp/xboxcodexbridge-clang-module-cache}"

cd "$project_root"
export SWIFT_MODULECACHE_PATH="$swift_module_cache"
export CLANG_MODULE_CACHE_PATH="$clang_module_cache"
/bin/mkdir -p "$swift_module_cache" "$clang_module_cache"
/usr/bin/env swift build --disable-sandbox -c release

/bin/mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/Web"
/bin/cp "$project_root/App/Info.plist" "$app_path/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$bundle_id" "$app_path/Contents/Info.plist"
/bin/cp "$release_path/XboxCodexBridge" "$app_path/Contents/MacOS/XboxCodexBridge"
for resource in "$project_root"/Sources/XboxCodexBridge/Web/*; do
  /bin/cp "$resource" "$app_path/Contents/Resources/Web/${resource:t}"
done

# The build directory can inherit Finder metadata when it is viewed or copied
# through Finder. Code signing rejects those attributes, so clear them only
# from this generated app bundle before signing.
/usr/bin/xattr -cr "$app_path"

if [[ -z "$signing_identity" ]]; then
  signing_identity="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/sed -n 's/^[[:space:]]*[0-9][0-9]*) [A-Fa-f0-9]* "\([^"]*\)".*/\1/p' \
      | /usr/bin/head -n 1
  )"
fi

if [[ -z "$signing_identity" ]]; then
  signing_identity="-"
fi

if [[ "$signing_identity" != "-" ]]; then
  identity_list="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ "$identity_list" != *"\"$signing_identity\""* ]]; then
    print -u2 "No valid code-signing identity named: $signing_identity"
    print -u2 "Set XBOX_CODE_SIGN_IDENTITY to '-' for ad-hoc signing or choose an identity from:"
    print -u2 "  security find-identity -v -p codesigning"
    exit 1
  fi
fi

/usr/bin/codesign --force --sign "$signing_identity" --identifier "$bundle_id" --timestamp=none "$app_path"
if [[ "$signing_identity" == "-" ]]; then
  signing_mode="ad-hoc identity"
else
  signing_mode="stable identity: $signing_identity"
fi

/usr/bin/codesign --verify --deep --strict "$app_path"
print "PACKAGED $app_path ($signing_mode)"
