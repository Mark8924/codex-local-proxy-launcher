#!/bin/zsh
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
app_bundle="${script_dir}/Codex Launcher.app"
resources_dir="${app_bundle}/Contents/Resources"
target_icon="${resources_dir}/icon.icns"

codex_app="${CODEX_APP_PATH:-/Applications/Codex.app/Contents/MacOS/Codex}"
codex_contents_dir="$(cd -- "$(dirname -- "$codex_app")/.." >/dev/null 2>&1 && pwd || true)"

candidates=(
  "${CODEX_ICON_PATH:-}"
  "${codex_contents_dir}/Resources/icon.icns"
  "${codex_contents_dir}/Resources/app.icns"
  "/Applications/Codex.app/Contents/Resources/icon.icns"
  "/Applications/Codex.app/Contents/Resources/app.icns"
)

for candidate in "${candidates[@]}"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    /bin/mkdir -p "$resources_dir"
    /bin/cp "$candidate" "$target_icon"
    /usr/bin/touch "$app_bundle"
    /usr/bin/osascript \
      -e 'on run argv' \
      -e 'tell application "Finder" to update POSIX file (item 1 of argv)' \
      -e 'end run' \
      "$app_bundle" >/dev/null 2>&1 || true
    /usr/bin/osascript -e 'display dialog "Codex Launcher icon installed. If Finder still shows the old icon, reopen this folder or relaunch Finder." buttons {"OK"} default button "OK"'
    exit 0
  fi
done

/usr/bin/osascript -e 'display dialog "Codex icon was not found. Install Codex.app first, or set CODEX_ICON_PATH to an .icns file." buttons {"OK"} default button "OK" with icon caution'
exit 1
