#!/usr/bin/env bash
# Builds TodoBar.app. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TodoBar"

APP="build/TodoBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TodoBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Rilakkuma Resources/Quby "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/TodoBar.app"
  pkill -x TodoBar || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
