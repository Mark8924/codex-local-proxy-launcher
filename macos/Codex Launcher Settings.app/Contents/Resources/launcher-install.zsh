#!/bin/zsh
set -euo pipefail
resources_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$resources_dir/launcher-maintenance.zsh"
replace_launcher_contents "$1" "$2"
