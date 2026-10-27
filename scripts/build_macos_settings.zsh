#!/bin/zsh
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
app="$root/macos/Codex Launcher Settings.app"
resources="$root/macos/Codex Launcher.app/Contents/Resources"
temporary="$(mktemp -d "${TMPDIR:-/tmp/}/launcher-settings-build.XXXXXXXX")"
trap '/bin/rm -rf "$temporary"' EXIT
/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
  /usr/bin/xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "$arch-apple-macosx12.0" \
    -module-cache-path "$temporary/cache" "$root/macos/settings/main.swift" -o "$temporary/$arch"
done
/usr/bin/lipo -create "$temporary/arm64" "$temporary/x86_64" -output "$app/Contents/MacOS/Launcher Settings"
/bin/cp "$root/macos/settings/Info.plist" "$app/Contents/Info.plist"
for name in launcher-common.zsh launcher-maintenance.zsh launcher-icon.zsh launcher-install.zsh; do
  /bin/cp "$resources/$name" "$app/Contents/Resources/$name"
done
iconset="$temporary/settings.iconset"
/bin/mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$root/macos/settings/assets/settings-icon.png" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$root/macos/settings/assets/settings-icon.png" \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/settings-icon.icns"
/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
