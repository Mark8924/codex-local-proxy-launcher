#!/bin/zsh
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
app_bundle="${script_dir}/Codex Launcher.app"
resources_dir="${app_bundle}/Contents/Resources"
target_icon="${resources_dir}/icon.icns"
source "${resources_dir}/launcher-common.zsh"
load_launcher_config "$script_dir"

codex_app="$(resolve_app_executable || true)"
codex_contents_dir=""
if [[ -n "$codex_app" ]]; then
  codex_contents_dir="${codex_app:h:h}"
fi

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

icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${codex_contents_dir}/Info.plist" 2>/dev/null || true)"
if [[ -n "$icon_name" && "$icon_name" != *.icns ]]; then
  icon_name="${icon_name}.icns"
fi

candidates=(
  "${CODEX_ICON_PATH:-}"
  "${codex_contents_dir}/Resources/${icon_name}"
  "${codex_contents_dir}/Resources/icon.icns"
  "${codex_contents_dir}/Resources/app.icns"
  "${codex_contents_dir}/Resources/electron.icns"
  "${codex_contents_dir}/Resources/icon-chatgpt.icns"
)
if [[ -n "${CODEX_ICON_PATH:-}" ]]; then
  candidates=("$CODEX_ICON_PATH")
fi

for candidate in "${candidates[@]}"; do
  if [[ -f "$candidate" ]]; then
    # Replace the directory entry, never write through an old icon symlink.
    temporary_icon="$(/usr/bin/mktemp "${resources_dir}/.icon.XXXXXXXX")"
    trap '/bin/rm -f "$temporary_icon"' EXIT
    /bin/cp "$candidate" "$temporary_icon"
    /bin/chmod 644 "$temporary_icon"
    /bin/mv -f "$temporary_icon" "$target_icon"
    /usr/bin/codesign --force --deep --sign - "$app_bundle"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"
    refresh_finder_icon
    /usr/bin/osascript -e 'display dialog "Codex Launcher icon installed and the app locally signed. If Finder still shows the old icon, reopen this folder." buttons {"OK"} default button "OK"'
    exit 0
  fi
done

/usr/bin/osascript -e 'display dialog "The ChatGPT/Codex icon was not found. Check CODEX_APP_PATH or CODEX_ICON_PATH in your launcher config." buttons {"OK"} default button "OK" with icon caution'
exit 1
