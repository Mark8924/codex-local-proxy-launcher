trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

load_config_file() {
  local file="$1"
  local line key value
  local double_quoted='^"(.*)"([[:space:]]+#.*)?$'
  local single_quoted="^'(.*)'([[:space:]]+#.*)?$"

  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#$'\xef\xbb\xbf'}"
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    if [[ "$value" =~ "$double_quoted" || "$value" =~ "$single_quoted" ]]; then
      value="$match[1]"
    else
      value="$(trim "${value%%[[:space:]]\#*}")"
    fi
    case "$key" in
      CODEX_PROXY_PORT|CODEX_PROXY_HOST|CODEX_PROXY_SCHEME|CODEX_PROXY_URL|CODEX_APP_PATH|CODEX_ICON_PATH|CODEX_ICON_STYLE|CODEX_ICON_APPEARANCE|CODEX_NO_PROXY)
        [[ "$key" == CODEX_APP_PATH && "${launcher_gui_app_auto:-0}" == 1 ]] && continue
        if [[ -z "${(P)key:-}" ]]; then
          export "$key=$value"
        fi
        ;;
    esac
  done < "$file"
  return 0
}

load_launcher_config() {
  local platform_dir="$1"
  local settings_file="${HOME}/Library/Application Support/codex-local-proxy-launcher/settings.json"
  local key value
  launcher_gui_app_auto=0
  if [[ -f "$settings_file" ]]; then
    for key in CODEX_PROXY_PORT CODEX_PROXY_HOST CODEX_PROXY_SCHEME CODEX_PROXY_URL CODEX_APP_PATH CODEX_NO_PROXY; do
      value="$(/usr/bin/plutil -extract "$key" raw -o - "$settings_file" 2>/dev/null || true)"
      if [[ -n "$value" && -z "${(P)key:-}" ]]; then
        export "$key=$value"
      fi
    done
    if [[ -z "${CODEX_APP_PATH:-}" ]] && /usr/bin/plutil -extract CODEX_APP_PATH raw -o /dev/null "$settings_file" 2>/dev/null; then
      launcher_gui_app_auto=1
    fi
  fi
  if [[ -n "${CODEX_PROXY_CONFIG:-}" ]]; then
    if [[ ! -f "$CODEX_PROXY_CONFIG" ]]; then
      print -u2 -- "Config file not found: $CODEX_PROXY_CONFIG"
      return 1
    fi
    load_config_file "$CODEX_PROXY_CONFIG"
  fi
  load_config_file "${platform_dir}/codex-proxy-launcher.env"
  load_config_file "${platform_dir:h}/codex-proxy-launcher.env"
  load_config_file "${HOME}/.codex-proxy-launcher.env"
}

resolve_app_executable() {
  local candidate executable_name executable_path bundle_id
  local candidates=(
    "/Applications/ChatGPT.app"
    "${HOME}/Applications/ChatGPT.app"
    "/Applications/Codex.app"
    "${HOME}/Applications/Codex.app"
  )
  if [[ -n "${CODEX_APP_PATH:-}" ]]; then
    candidates=("$CODEX_APP_PATH")
  fi

  for candidate in "${candidates[@]}"; do
    executable_path="$candidate"
    if [[ -d "$candidate" && -f "${candidate}/Contents/Info.plist" ]]; then
      # An older, separate ChatGPT app may coexist with Codex.
      if [[ -z "${CODEX_APP_PATH:-}" && "${candidate:t}" == ChatGPT.app ]]; then
        bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null || true)"
        [[ "$bundle_id" == com.openai.codex || -x "${candidate}/Contents/Resources/codex" ]] || continue
      fi
      executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${candidate}/Contents/Info.plist" 2>/dev/null || true)"
      [[ -n "$executable_name" ]] || continue
      executable_path="${candidate}/Contents/MacOS/${executable_name}"
    fi
    if [[ -f "$executable_path" && -x "$executable_path" ]]; then
      printf "%s" "${executable_path:A}"
      return 0
    fi
  done
  return 1
}

configure_proxy() {
  local requested_port="${1:-${CODEX_PROXY_PORT:-10808}}"
  local scheme="${CODEX_PROXY_SCHEME:-http}"
  local host="${CODEX_PROXY_HOST:-127.0.0.1}"
  local authority host_port
  proxy_error=""

  if [[ -n "${CODEX_PROXY_URL:-}" ]]; then
    proxy_url="$CODEX_PROXY_URL"
    if [[ "$proxy_url" != *://* ]]; then
      proxy_error="Invalid CODEX_PROXY_URL: use http://host:port or https://host:port."
      return 1
    fi
    scheme="${proxy_url%%://*}"
    authority="${proxy_url#*://}"
    authority="${authority%/}"
    if [[ -z "$authority" || "$authority" == *[[:space:]/\?\#]* ]]; then
      proxy_error="Invalid CODEX_PROXY_URL: paths, query strings and fragments are not supported."
      return 1
    fi
    host_port="${authority##*@}"
    if [[ "$host_port" == \[* ]]; then
      if [[ "$host_port" != *\]* ]]; then
        proxy_error="Invalid CODEX_PROXY_URL: enclose IPv6 addresses in brackets."
        return 1
      fi
      host="${host_port#\[}"
      host="${host%%\]*}"
      requested_port="${host_port#*\]}"
      if [[ -n "$requested_port" && "$requested_port" != :* ]]; then
        proxy_error="Invalid CODEX_PROXY_URL."
        return 1
      fi
      requested_port="${requested_port#:}"
      [[ "$host_port" == *\]: ]] && requested_port="invalid"
    else
      host="${host_port%%:*}"
      if [[ "$host_port" == *:* ]]; then
        requested_port="${host_port#*:}"
        [[ -n "$requested_port" ]] || requested_port="invalid"
      else
        requested_port=""
      fi
    fi
    if [[ -z "$requested_port" ]]; then
      [[ "${scheme:l}" == https ]] && requested_port=443 || requested_port=80
    fi
  else
    host="${host#\[}"
    host="${host%\]}"
    if [[ "$host" == *:* ]]; then
      proxy_url="${scheme}://[${host}]:${requested_port}"
    else
      proxy_url="${scheme}://${host}:${requested_port}"
    fi
  fi

  if [[ "${scheme:l}" != http && "${scheme:l}" != https ]]; then
    proxy_error="Use an HTTP or HTTPS proxy URL, not a SOCKS-only endpoint."
    return 1
  fi
  if [[ -z "$host" || "$host" == -* || "$host" == *[[:space:]/@\?\#\[\]]* ]]; then
    proxy_error="Invalid proxy host."
    return 1
  fi
  if [[ "$requested_port" != <-> || ${#requested_port} -gt 5 ]]; then
    proxy_error="Invalid proxy port: use a number from 1 to 65535."
    return 1
  fi
  check_port=$((10#$requested_port))
  if (( check_port < 1 || check_port > 65535 )); then
    proxy_error="Invalid proxy port: use a number from 1 to 65535."
    return 1
  fi
  check_host="$host"
}

find_running_app() {
  local executable="$1"
  local pid command
  while read -r pid command; do
    if [[ "$command" == "$executable" ]]; then
      printf "%s" "$pid"
      return 0
    fi
  done < <(/bin/ps -axww -o pid=,comm=)
  return 1
}
