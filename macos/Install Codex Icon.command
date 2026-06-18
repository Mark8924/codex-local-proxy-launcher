#!/bin/zsh
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
app_bundle="${script_dir}/Codex Launcher.app"
resources_dir="${app_bundle}/Contents/Resources"
target_icon="${resources_dir}/icon.icns"

codex_app="${CODEX_APP_PATH:-/Applications/Codex.app/Contents/MacOS/Codex}"
if [[ ! -x "$codex_app" && -x "${HOME}/Applications/Codex.app/Contents/MacOS/Codex" ]]; then
  codex_app="${HOME}/Applications/Codex.app/Contents/MacOS/Codex"
fi
codex_contents_dir="$(cd -- "$(dirname -- "$codex_app")/.." >/dev/null 2>&1 && pwd || true)"

refresh_finder_icon() {
  /usr/bin/touch "$app_bundle"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$app_bundle" >/dev/null 2>&1 || true
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'tell application "Finder" to update POSIX file (item 1 of argv)' \
    -e 'end run' \
    "$app_bundle" >/dev/null 2>&1 || true
}

sign_launcher_app() {
  /usr/bin/codesign --force --deep --sign - "$app_bundle"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"
}

if [[ -f "$target_icon" && ! -L "$target_icon" ]]; then
  sign_launcher_app
  refresh_finder_icon
  /usr/bin/osascript -e 'display dialog "Codex Launcher icon is already available, and the app has been locally signed. If Finder still shows the old icon, reopen this folder or relaunch Finder." buttons {"OK"} default button "OK"'
  exit 0
fi

icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${codex_contents_dir}/Info.plist" 2>/dev/null || true)"
icon_source=""
if [[ -n "$icon_name" ]]; then
  [[ "$icon_name" == *.icns ]] || icon_name="${icon_name}.icns"
  icon_source="${codex_contents_dir}/Resources/${icon_name}"
fi

candidates=(
  "${CODEX_ICON_PATH:-}"
  "$icon_source"
  "${codex_contents_dir}/Resources/icon.icns"
  "${codex_contents_dir}/Resources/app.icns"
  "${codex_contents_dir}/Resources/electron.icns"
  "/Applications/Codex.app/Contents/Resources/icon.icns"
  "/Applications/Codex.app/Contents/Resources/app.icns"
  "/Applications/Codex.app/Contents/Resources/electron.icns"
  "${HOME}/Applications/Codex.app/Contents/Resources/icon.icns"
  "${HOME}/Applications/Codex.app/Contents/Resources/app.icns"
  "${HOME}/Applications/Codex.app/Contents/Resources/electron.icns"
)

for candidate in "${candidates[@]}"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    /bin/mkdir -p "$resources_dir"
    if [[ -e "$target_icon" || -L "$target_icon" ]]; then
      /bin/rm -f "$target_icon"
    fi
    /bin/cp "$candidate" "$target_icon"
    sign_launcher_app
    refresh_finder_icon
    /usr/bin/osascript -e 'display dialog "Codex Launcher icon installed, and the app has been locally signed. If Finder still shows the old icon, reopen this folder or relaunch Finder." buttons {"OK"} default button "OK"'
    exit 0
  fi
done

/usr/bin/osascript -e 'display dialog "Codex icon was not found. Install Codex.app first, or set CODEX_ICON_PATH to an .icns file." buttons {"OK"} default button "OK" with icon caution'
exit 1
