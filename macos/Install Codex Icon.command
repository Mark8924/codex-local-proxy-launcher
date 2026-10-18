#!/bin/zsh
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
exec /bin/zsh "$script_dir/Codex Launcher.app/Contents/Resources/launcher-icon.zsh" "$@"
