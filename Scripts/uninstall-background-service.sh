#!/bin/zsh
set -euo pipefail

label="io.github.cyq1017.xbox-codex-bridge"
legacy_label="com.caoyuqi.xbox-codex-bridge"
app_destination="$HOME/Applications/XboxCodexBridge.app"
support_directory="$HOME/Library/Application Support/XboxCodexBridge"
purge=false

case "${1:-}" in
  "") ;;
  --purge) purge=true ;;
  *)
    print -u2 "Usage: $0 [--purge]"
    exit 2
    ;;
esac

for installed_label in "$label" "$legacy_label"; do
  if /bin/launchctl print "gui/$UID/$installed_label" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$UID/$installed_label"
  fi
  /bin/rm -f "$HOME/Library/LaunchAgents/$installed_label.plist"
done

/bin/rm -rf "$app_destination"

if [[ "$purge" == true ]]; then
  /bin/rm -rf "$support_directory"
  /bin/rm -f \
    "$HOME/Library/Logs/XboxCodexBridge.log" \
    "$HOME/Library/Logs/XboxCodexBridge.error.log"
  print "Xbox Codex Bridge and its local configuration were removed."
else
  print "Xbox Codex Bridge was removed. Local mappings were kept in:"
  print "  $support_directory"
  print "Run '$0 --purge' to remove them as well."
fi
