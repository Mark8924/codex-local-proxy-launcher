#!/bin/zsh
set -euo pipefail
setopt NO_BG_NICE 2>/dev/null || true

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
macos_dir="$(cd -- "${script_dir}/../../.." && pwd)"
repo_dir="$(cd -- "${macos_dir}/.." && pwd)"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

load_config_file() {
  local file="$1"
  local line key value

  [[ -f "$file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(trim "${line%%#*}")"
    [[ -z "$line" || "$line" != *=* ]] && continue

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"

    case "$key" in
      CODEX_PROXY_PORT)
        [[ -z "${CODEX_PROXY_PORT:-}" ]] && export CODEX_PROXY_PORT="$value"
        ;;
      CODEX_PROXY_HOST)
        [[ -z "${CODEX_PROXY_HOST:-}" ]] && export CODEX_PROXY_HOST="$value"
        ;;
      CODEX_PROXY_SCHEME)
        [[ -z "${CODEX_PROXY_SCHEME:-}" ]] && export CODEX_PROXY_SCHEME="$value"
        ;;
      CODEX_PROXY_URL)
        [[ -z "${CODEX_PROXY_URL:-}" ]] && export CODEX_PROXY_URL="$value"
        ;;
      CODEX_APP_PATH)
        [[ -z "${CODEX_APP_PATH:-}" ]] && export CODEX_APP_PATH="$value"
        ;;
      CODEX_ICON_PATH)
        [[ -z "${CODEX_ICON_PATH:-}" ]] && export CODEX_ICON_PATH="$value"
        ;;
      CODEX_NO_PROXY)
        [[ -z "${CODEX_NO_PROXY:-}" ]] && export CODEX_NO_PROXY="$value"
        ;;
    esac
  done < "$file"
}

show_dialog() {
  local message="$1"
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon caution' \
    -e 'end run' \
    "$message" >/dev/null
}

if [[ -n "${CODEX_PROXY_CONFIG:-}" ]]; then
  load_config_file "$CODEX_PROXY_CONFIG"
fi
load_config_file "${macos_dir}/codex-proxy-launcher.env"
load_config_file "${repo_dir}/codex-proxy-launcher.env"
load_config_file "${HOME}/.codex-proxy-launcher.env"

proxy_port="${1:-${CODEX_PROXY_PORT:-10808}}"
proxy_host="${CODEX_PROXY_HOST:-127.0.0.1}"
proxy_scheme="${CODEX_PROXY_SCHEME:-http}"
proxy_url="${CODEX_PROXY_URL:-${proxy_scheme}://${proxy_host}:${proxy_port}}"
codex_app="${CODEX_APP_PATH:-/Applications/Codex.app/Contents/MacOS/Codex}"
if [[ ! -x "$codex_app" && -x "${HOME}/Applications/Codex.app/Contents/MacOS/Codex" ]]; then
  codex_app="${HOME}/Applications/Codex.app/Contents/MacOS/Codex"
fi
no_proxy_value="${CODEX_NO_PROXY:-localhost,127.0.0.1,::1}"

check_host="$proxy_host"
check_port="$proxy_port"
if [[ -n "${CODEX_PROXY_URL:-}" ]]; then
  host_port="${proxy_url#*://}"
  host_port="${host_port%%/*}"
  check_host="${host_port%%:*}"
  check_port="${host_port##*:}"
fi

if [[ ! "$check_port" == <-> ]]; then
  show_dialog "Invalid proxy port: ${check_port}"
  exit 1
fi

if [[ ! -x "$codex_app" ]]; then
  show_dialog "Codex.app was not found at ${codex_app}. Set CODEX_APP_PATH if Codex is installed somewhere else."
  exit 1
fi

if ! /usr/bin/nc -z "$check_host" "$check_port" >/dev/null 2>&1; then
  show_dialog "Proxy ${check_host}:${check_port} is not listening. Start your proxy client first, then open Codex Launcher again."
  exit 1
fi

if /usr/bin/pgrep -x Codex >/dev/null 2>&1; then
  show_dialog "Codex is already running. Quit Codex completely, then open Codex Launcher so it can inherit the proxy environment."
  exit 1
fi

export HTTP_PROXY="$proxy_url"
export HTTPS_PROXY="$proxy_url"
export ALL_PROXY="$proxy_url"
export NO_PROXY="$no_proxy_value"
export http_proxy="$proxy_url"
export https_proxy="$proxy_url"
export all_proxy="$proxy_url"
export no_proxy="$no_proxy_value"

"$codex_app" >/tmp/codex-proxy-launcher.log 2>&1 &!
