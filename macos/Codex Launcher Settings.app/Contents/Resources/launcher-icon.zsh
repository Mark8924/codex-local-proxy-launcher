#!/bin/zsh
set -euo pipefail

resources_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$resources_dir/launcher-common.zsh"
source "$resources_dir/launcher-maintenance.zsh"
app_bundle="${resources_dir:h:h}"
config_dir="${app_bundle:h}"
style_argument="" appearance_argument="" choose=0 quiet=0 work_dir=""

finish_icon_change() {
  local result=$?
  trap - EXIT
  [[ -z "$work_dir" ]] || /bin/rm -rf "$work_dir"
  if (( result != 0 && ! quiet )); then
    /usr/bin/osascript -e 'display dialog "图标没有更换。请查看终端错误信息，确认 ChatGPT/Codex 已安装，且启动器目录可以写入。" with title "更换 Codex Launcher 图标" buttons {"好"} default button "好" with icon caution' || true
  fi
  exit "$result"
}
trap finish_icon_change EXIT

while (( $# )); do
  case "$1" in
    --app|--config-dir|--style|--appearance)
      (( $# >= 2 )) || { print -u2 -- "Missing value for $1"; exit 1; }
      case "$1" in
        --app) app_bundle="$2" ;;
        --config-dir) config_dir="$2" ;;
        --style) style_argument="$2" ;;
        --appearance) appearance_argument="$2" ;;
      esac
      shift 2 ;;
    --choose) choose=1; shift ;;
    --no-dialog) quiet=1; shift ;;
    *) print -u2 -- "Unknown option: $1"; exit 1 ;;
  esac
done
load_launcher_config "$config_dir"
style="${style_argument:-${CODEX_ICON_STYLE:-auto}}"
appearance="${appearance_argument:-${CODEX_ICON_APPEARANCE:-auto}}"
if (( choose )); then
  selection="$(/usr/bin/osascript \
    -e 'set selectedIcon to choose from list {"ChatGPT", "Codex", "Space"} with title "更换 Codex Launcher 图标" with prompt "从本机 ChatGPT 的三套图标中选择：" default items {"ChatGPT"} OK button name "更换" cancel button name "取消"' \
    -e 'if selectedIcon is false then return "cancel"' \
    -e 'return item 1 of selectedIcon')"
  [[ "$selection" != cancel ]] || exit 0
  style="${selection:l}"
fi
[[ "$style" == (auto|chatgpt|codex|space) ]] || { print -u2 -- "Invalid icon style: $style"; exit 1; }
[[ "$appearance" == (auto|light|dark) ]] || { print -u2 -- "Invalid icon appearance: $appearance"; exit 1; }
if [[ "$appearance" == auto ]]; then
  appearance=light
  [[ "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null || true)" != Dark ]] || appearance=dark
fi

executable="$(resolve_app_executable || true)"
source_resources="${executable:h:h}/Resources"
candidate=""
if [[ "$style" == auto ]]; then
  if [[ -n "${CODEX_ICON_PATH:-}" ]]; then
    candidate="$CODEX_ICON_PATH"
  else
    icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${source_resources:h}/Info.plist" 2>/dev/null || true)"
    [[ -z "$icon_name" || "$icon_name" == *.icns ]] || icon_name+=".icns"
    for icon_path in "$source_resources/$icon_name" "$source_resources/icon.icns" "$source_resources/app.icns" "$source_resources/electron.icns" "$source_resources/icon-chatgpt.icns"; do
      if [[ -f "$icon_path" ]]; then candidate="$icon_path"; break; fi
    done
  fi
else
  case "$style" in
    chatgpt) candidate="$source_resources/icon-chatgpt.icns"
      [[ -f "$candidate" ]] || candidate="$source_resources/icon-chatgpt.png" ;;
    codex)
      [[ "$appearance" == dark ]] && candidate="$source_resources/icon-codex-dark-color.png" || candidate="$source_resources/icon-codex-light.png" ;;
    space) candidate="$source_resources/icon-space-$appearance.png" ;;
  esac
fi
[[ -f "$candidate" ]] || { print -u2 -- "Icon not found: $candidate"; exit 1; }
[[ -d "$app_bundle/Contents" ]] || { print -u2 -- "Launcher not found: $app_bundle"; exit 1; }
work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}/codex-launcher-icon.XXXXXXXX")"
staged_app="$work_dir/Codex Launcher.app"
/usr/bin/ditto --norsrc --noextattr --noqtn "$app_bundle" "$staged_app"
target_icon="$staged_app/Contents/Resources/icon.icns"
# Do not write through an icon symlink left by an older launcher.
/bin/rm -f "$target_icon"
if [[ "${candidate:e:l}" == icns ]]; then
  /bin/cp -X "$candidate" "$target_icon"
else
  iconset="$work_dir/Launcher.iconset"
  /bin/mkdir "$iconset"
  for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$candidate" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$candidate" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  /usr/bin/iconutil -c icns "$iconset" -o "$target_icon"
fi
/bin/chmod 644 "$target_icon"
clean_signing_metadata "$staged_app"
/usr/bin/codesign --force --deep --sign - "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"
if [[ -w "$app_bundle" && -w "${app_bundle:h}" ]]; then
  /bin/zsh "$resources_dir/launcher-install.zsh" "$staged_app" "$app_bundle"
else
  /usr/bin/osascript -e 'on run argv' \
    -e 'do shell script ("/bin/zsh " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv) & " " & quoted form of (item 3 of argv)) with administrator privileges' \
    -e 'end run' "$resources_dir/launcher-install.zsh" "$staged_app" "$app_bundle"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_bundle" >/dev/null 2>&1 || true
if (( ! quiet )); then
  /usr/bin/osascript -e 'on run argv' \
    -e 'tell application "Finder" to update POSIX file (item 1 of argv)' \
    -e 'display dialog "图标已更换，Dock 中的启动入口保持不变。缓存可能稍后刷新，无需重启 ChatGPT。" with title "更换 Codex Launcher 图标" buttons {"好"} default button "好"' \
    -e 'end run' "$app_bundle"
fi
