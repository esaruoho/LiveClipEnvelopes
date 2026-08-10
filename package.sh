#!/bin/bash
# Builds a distributable zip: the prebuilt app, the CLI, the AbletonOSC patch,
# the Keyboard Maestro macros, the Shortcuts, and a short install README.
#
# Usage: ./package.sh            -> LiveClipEnvelopes-<version>-macOS.zip
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0}"
STAGE=$(mktemp -d)
NAME="LiveClipEnvelopes-${VERSION}-macOS"
OUT="$PWD/${NAME}.zip"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | rg -o '"[^"]+"' | head -1 | tr -d '"' || true)

echo "==> Building CLI"
mkdir -p "$STAGE/$NAME/bin"
swiftc -O -o "$STAGE/$NAME/bin/live-envelope" bin/live-envelope.swift

echo "==> Building Live Envelopes.app"
APP="$STAGE/$NAME/Live Envelopes.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/LiveEnvelopePanel" LiveEnvelopePanel/main.swift
cp LiveEnvelopePanel/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/<string>1.0<\/string>/<string>${VERSION}<\/string>/" > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>LiveEnvelopePanel</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.esaruoho.LiveEnvelopePanel</string>
	<key>CFBundleName</key>
	<string>Live Envelopes</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

if [ -n "$IDENTITY" ]; then
    codesign --force --deep -s "$IDENTITY" "$APP" >/dev/null 2>&1
    echo "    signed with $IDENTITY"
else
    codesign --force --deep -s - "$APP" >/dev/null 2>&1
    echo "    signed ad-hoc (no identity found)"
fi

echo "==> Staging support files"
cp -R abletonosc-patch keyboard-maestro "$STAGE/$NAME/"
mkdir -p "$STAGE/$NAME/shortcuts"
cp shortcuts/signed/*.shortcut "$STAGE/$NAME/shortcuts/"
cp LICENSE README.md "$STAGE/$NAME/"

cat > "$STAGE/$NAME/INSTALL.txt" <<'TXT'
LiveClipEnvelopes — install
===========================

1. Drag "Live Envelopes.app" to /Applications, then open it.
   First click will ask for Accessibility permission:
   System Settings > Privacy & Security > Accessibility.
   This is required -- the app works by driving Live's own UI.

2. Install the CLI (needed by the app, the macros and the Shortcuts):

       sudo cp bin/live-envelope /usr/local/bin/live-envelope
       sudo chmod 755 /usr/local/bin/live-envelope

3. Install AbletonOSC if you don't have it:
       https://github.com/ideoforms/AbletonOSC
   Then copy the patched view.py over it, so the transpose buttons and the
   "show the Envelopes box" fallback work:

       cp abletonosc-patch/view.py <AbletonOSC>/abletonosc/view.py

   Restart Live (or send OSC to /live/api/reload).

4. Optional:
   - keyboard-maestro/*.kmmacros -- double-click to import (no triggers assigned;
     add your own hot keys, MIDI notes or mouse buttons)
   - shortcuts/*.shortcut -- double-click each to add to Shortcuts.app

See README.md for the full command list and how it works.

Source: https://github.com/esaruoho/LiveClipEnvelopes
TXT

echo "==> Zipping"
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" "$NAME" -x '*.DS_Store')
rm -rf "$STAGE"

echo "==> $OUT"
ls -lh "$OUT" | awk '{print "    " $5}'
unzip -l "$OUT" | tail -3
