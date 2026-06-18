#!/bin/zsh
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
app_bundle="${script_dir}/Codex Launcher.app"

show_dialog() {
  local message="$1"
  local icon="${2:-note}"
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon (item 2 of argv)' \
    -e 'end run' \
    "$message" "$icon" >/dev/null
}

if [[ ! -d "$app_bundle" ]]; then
  show_dialog "Codex Launcher.app was not found next to this script." "caution"
  exit 1
fi

/usr/bin/codesign --force --deep --sign - "$app_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"

show_dialog "Codex Launcher.app has been locally signed. If macOS previously remembered a broken permission entry, remove the old entry from System Settings and add the app again." "note"
