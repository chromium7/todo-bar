#!/usr/bin/env bash
# Builds TodoBar.app.
#   --install  also copy it to ~/Applications and launch it
#   --dist     build a universal (Apple Silicon + Intel) app and zip it to
#              build/TodoBar.zip, ready to copy to another Mac (no Xcode needed there)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP="build/TodoBar.app"

if [[ "$MODE" == "--dist" ]]; then
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  ARM="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path 2>/dev/null)/TodoBar"
  X86="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path 2>/dev/null)/TodoBar"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/TodoBar"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$MODE" == "--dist" ]]; then
  lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/TodoBar"
else
  cp "$BIN" "$APP/Contents/MacOS/TodoBar"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Rilakkuma Resources/Quby "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "$MODE" == "--install" ]]; then
  DEST="$HOME/Applications/TodoBar.app"
  pkill -x TodoBar || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi

if [[ "$MODE" == "--dist" ]]; then
  ZIP="build/TodoBar.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Packaged $ZIP ($(lipo -archs "$APP/Contents/MacOS/TodoBar"))"
fi
