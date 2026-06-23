#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

swift build -c release --product QuotaFloat
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/QuotaFloat.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/QuotaFloat" "$APP/Contents/MacOS/QuotaFloat"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/QuotaFloat-LICENSE.txt"
cp "$ROOT/PRIVACY.md" "$APP/Contents/Resources/PRIVACY.md"
cp "$ROOT/ThirdPartyLicenses/CodexBar-LICENSE.txt" "$APP/Contents/Resources/CodexBar-LICENSE.txt"
if [[ -d "$BIN_DIR/QuotaFloat_QuotaFloat.bundle" ]]; then
  cp -R "$BIN_DIR/QuotaFloat_QuotaFloat.bundle" "$APP/Contents/Resources/"
  rm -f "$APP/Contents/Resources/QuotaFloat_QuotaFloat.bundle/claude-mark.png"
fi
chmod +x "$APP/Contents/MacOS/QuotaFloat"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/QuotaFloat")"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Expected an Apple Silicon arm64 build, got: $ARCHS" >&2
  exit 1
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP"
fi

echo "$APP"
