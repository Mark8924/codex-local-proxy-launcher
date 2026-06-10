#!/bin/zsh
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
exec "${script_dir}/Codex Launcher.app/Contents/MacOS/Codex Launcher" "$@"
