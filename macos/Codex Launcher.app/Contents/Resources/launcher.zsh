#!/bin/zsh
set -euo pipefail
setopt NO_BG_NICE

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
macos_dir="$(cd -- "${script_dir}/../../.." && pwd)"
source "${script_dir}/launcher-common.zsh"

show_dialog() {
  local message="$1"
  print -u2 -- "$message"
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon caution' \
    -e 'end run' \
    "$message" >/dev/null
}

if ! load_launcher_config "$macos_dir"; then
  show_dialog "Cannot read the configuration specified by CODEX_PROXY_CONFIG."
  exit 1
fi
if ! configure_proxy "${1:-}"; then
  show_dialog "$proxy_error"
  exit 1
fi
if ! codex_app="$(resolve_app_executable)"; then
  show_dialog "ChatGPT.app or Codex.app was not found. Check CODEX_APP_PATH if set; it must point to an .app bundle or an executable file."
  exit 1
fi

running_pid="$(find_running_app "$codex_app" || true)"
if [[ -n "$running_pid" ]]; then
  show_dialog "${codex_app:t} is already running (PID $running_pid). Quit it completely, then open Codex Launcher so the new process can inherit the proxy environment."
  exit 1
fi
if ! /usr/bin/nc -z -G 3 -w 3 "$check_host" "$check_port" >/dev/null 2>&1; then
  show_dialog "Proxy ${check_host}:${check_port} is not listening. Start your proxy client first, then open Codex Launcher again."
  exit 1
fi

no_proxy_value="${CODEX_NO_PROXY:-localhost,127.0.0.1,::1}"
export HTTP_PROXY="$proxy_url"
export HTTPS_PROXY="$proxy_url"
export ALL_PROXY="$proxy_url"
export NO_PROXY="$no_proxy_value"
export http_proxy="$proxy_url"
export https_proxy="$proxy_url"
export all_proxy="$proxy_url"
export no_proxy="$no_proxy_value"

log_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}/codex-proxy-launcher.XXXXXXXX")"
"$codex_app" >"$log_file" 2>&1 &
launch_pid=$!
/bin/sleep 0.3
if [[ -n "$(jobs -r)" ]]; then
  disown %1
else
  if wait "$launch_pid"; then
    exit 0
  else
    launch_status=$?
    show_dialog "${codex_app:t} failed to start (exit $launch_status). Details: $log_file"
    exit "$launch_status"
  fi
fi
