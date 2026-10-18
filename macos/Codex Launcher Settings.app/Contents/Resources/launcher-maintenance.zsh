# Finder may attach these attributes to an app even when its contents are signed.
clean_signing_metadata() {
  local app="$1" attribute
  for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
    /usr/bin/xattr -dr "$attribute" "$app" 2>/dev/null || true
  done
}

replace_launcher_contents() (
  set -euo pipefail
  local staged_app="$1" target_app="$2" scratch attribute metadata
  local metadata_changed=0
  [[ -d "$staged_app/Contents" && -d "$target_app/Contents" ]]
  local bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staged_app/Contents/Info.plist")"
  local target_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")"
  [[ "$bundle_id" == io.github.codex-proxy-launcher && "$target_id" == "$bundle_id" ]]
  /usr/bin/codesign --verify --deep --strict "$staged_app"
  scratch="$(/usr/bin/mktemp -d "${target_app:h}/.codex-launcher-update.XXXXXXXX")"
  finish_transaction() {
    local result=$? rollback_failed=0
    trap - EXIT
    set +e
    if (( result != 0 )) && [[ -d "$scratch/previous" ]]; then
      if [[ -e "$target_app/Contents" ]]; then
        /bin/mv "$target_app/Contents" "$scratch/failed" || rollback_failed=1
      fi
      if (( rollback_failed == 0 )); then
        /bin/mv "$scratch/previous" "$target_app/Contents" || rollback_failed=1
      fi
    fi
    if (( result != 0 && metadata_changed )); then
      for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
        metadata="$scratch/$attribute"
        if [[ -f "$metadata" ]]; then
          /usr/bin/xattr -wx "$attribute" "$(<"$metadata")" "$target_app" || rollback_failed=1
        fi
      done
    fi
    if (( rollback_failed )); then
      print -u2 -- "Rollback needs attention. Backup retained at: $scratch"
      exit 1
    fi
    /bin/rm -rf "$scratch"
    exit "$result"
  }
  trap finish_transaction EXIT
  for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
    if ! /usr/bin/xattr -px "$attribute" "$target_app" > "$scratch/$attribute" 2>/dev/null; then
      /bin/rm -f "$scratch/$attribute"
    fi
  done
  /usr/bin/ditto --norsrc --noextattr --noqtn "$staged_app/Contents" "$scratch/Contents"
  /bin/mv "$target_app/Contents" "$scratch/previous"
  /bin/mv "$scratch/Contents" "$target_app/Contents"
  metadata_changed=1
  for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
    if [[ -f "$scratch/$attribute" ]]; then
      /usr/bin/xattr -d "$attribute" "$target_app"
    fi
  done
  /usr/bin/codesign --verify --deep --strict "$target_app"
  /usr/bin/touch "$target_app"
)
