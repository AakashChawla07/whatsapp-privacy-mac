#!/usr/bin/env bash
# Builds WhatsApp Privacy Blur.app into ./build.
#
# Usage: scripts/build-app.sh [debug|release]   (default: release)
#
# Signing: set SIGN_IDENTITY to a stable identity (e.g. "Apple Development: …" or "Developer ID Application: …").
# macOS ties the Accessibility grant to the code signature, so ad-hoc signing ("-", the default)
# means re-granting Accessibility after every rebuild.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/WhatsApp Privacy Blur.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG" --product WhatsAppPrivacyBlur
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WhatsAppPrivacyBlur" "$APP/Contents/MacOS/WhatsAppPrivacyBlur"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "Built: $APP"
