#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
label="io.github.cyq1017.xbox-codex-bridge"
legacy_label="com.caoyuqi.xbox-codex-bridge"
app_source="$project_root/.build/XboxCodexBridge.app"
app_destination="$HOME/Applications/XboxCodexBridge.app"
support_directory="$HOME/Library/Application Support/XboxCodexBridge"
launch_agent_source="$project_root/LaunchAgent/$label.plist"
launch_agent_destination="$HOME/Library/LaunchAgents/$label.plist"
rendered_launch_agent="$(/usr/bin/mktemp "${TMPDIR:-/private/tmp}/$label.XXXXXX.plist")"
trap '/bin/rm -f "$rendered_launch_agent"' EXIT

"$project_root/Scripts/package-app.sh"

/bin/mkdir -p "$HOME/Applications" "$support_directory" "$HOME/Library/LaunchAgents"
/usr/bin/ditto "$app_source" "$app_destination"
/usr/bin/codesign --verify --deep --strict "$app_destination"

/usr/bin/sed "s|@HOME@|$HOME|g" "$launch_agent_source" > "$rendered_launch_agent"
/usr/bin/plutil -lint "$rendered_launch_agent" >/dev/null
/usr/bin/ditto "$rendered_launch_agent" "$launch_agent_destination"

# Run once as a distinct installed app instance so macOS can present its
# Accessibility consent UI for this exact bundle identity. Setup exits before
# creating a listener, so it cannot contend with the already-running service.
/usr/bin/open -n -W -g "$app_destination" --args --request-accessibility || true

for installed_label in "$label" "$legacy_label"; do
  if /bin/launchctl print "gui/$UID/$installed_label" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$UID/$installed_label"
  fi
done
/bin/rm -f "$HOME/Library/LaunchAgents/$legacy_label.plist"
/bin/launchctl bootstrap "gui/$UID" "$launch_agent_destination"
/bin/launchctl kickstart -k "gui/$UID/$label"

print "Installed and started $label"
print "Dashboard: http://127.0.0.1:8765/"
print "If macOS opened Accessibility settings, enable Xbox Codex Bridge once, then rerun this script."
