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
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' || true)
IDENTITY=$(printf '%s\n' "$IDENTITIES" | grep -m1 '^Developer ID Application' || true)
[ -n "$IDENTITY" ] || IDENTITY=$(printf '%s\n' "$IDENTITIES" | grep -m1 . || true)

echo "==> Building CLI"
mkdir -p "$STAGE/$NAME/bin"
swiftc -O -o "$STAGE/$NAME/bin/live-envelope" bin/live-envelope.swift

echo "==> Building Live Envelopes.app"
APP="$STAGE/$NAME/Live Envelopes.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/LiveEnvelopePanel" LiveEnvelopePanel/main.swift
cp LiveEnvelopePanel/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Help reads this from inside the bundle, so it works with no network.
cp README.md "$APP/Contents/Resources/README.md"
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

# The app runs this copy; it is signed as part of the bundle, so the app's Accessibility
# grant covers it and there is no second binary anywhere to drift out of date.
cp "$STAGE/$NAME/bin/live-envelope" "$APP/Contents/MacOS/live-envelope"
chmod 755 "$APP/Contents/MacOS/live-envelope"
echo "    embedded live-envelope in the bundle"

if [ -n "$IDENTITY" ]; then
    codesign --force --deep --identifier com.esaruoho.LiveEnvelopePanel \
             -s "$IDENTITY" "$APP" >/dev/null 2>&1
    echo "    signed with $IDENTITY"
else
    codesign --force --deep -s - "$APP" >/dev/null 2>&1
    echo "    signed ad-hoc (no identity found)"
fi

echo "==> Staging support files"
cp -R abletonosc-patch keyboard-maestro "$STAGE/$NAME/"
mkdir -p "$STAGE/$NAME/shortcuts"

#--------------------------------------------------------------------------------
# Sign any Shortcut that is missing or older than its .wflow source. The signed files
# are build output, so regenerating them here means a release can never go out with
# them stale or absent -- which is exactly what happened when they were deleted by
# hand and packaging failed with "No such file or directory".
#--------------------------------------------------------------------------------
mkdir -p shortcuts/signed
signed_count=0
for wflow in shortcuts/unsigned/*.wflow; do
    base=$(basename "$wflow" .wflow)
    out="shortcuts/signed/$base.shortcut"
    if [ ! -f "$out" ] || [ "$wflow" -nt "$out" ]; then
        shortcuts sign --mode anyone --input "$wflow" --output "$out"
        signed_count=$((signed_count + 1))
    fi
done
[ "$signed_count" -gt 0 ] && echo "    re-signed $signed_count shortcut(s)"
cp shortcuts/signed/*.shortcut "$STAGE/$NAME/shortcuts/"
echo "    staged $(ls shortcuts/signed/*.shortcut | wc -l | tr -d ' ') shortcuts"
cp LICENSE README.md "$STAGE/$NAME/"

cat > "$STAGE/$NAME/READ ME FIRST - if macOS blocks the app.txt" <<'TXT'
macOS will refuse to open Live Envelopes.app the first time, saying it cannot verify
the developer. That is expected: the app is signed, but not notarized by Apple.

Fix it in one line. Move the app to /Applications first, then paste this into
Terminal (Applications > Utilities > Terminal) and press Return:

    xattr -dr com.apple.quarantine "/Applications/Live Envelopes.app"

Then open the app normally. Done -- it will never ask again.

What that does: macOS flags anything downloaded from a browser, and Gatekeeper only
blocks flagged files. The command removes the flag from this one app. It changes no
system setting and affects nothing else.

Prefer not to use Terminal?
  1. Double-click the app, click Done on the warning.
  2. System Settings > Privacy & Security > scroll to Security.
  3. "Open Anyway" next to "Live Envelopes.app was blocked" > authenticate > Open.

(Control-click > Open no longer works on macOS 15 Sequoia; Apple removed it.)
TXT

cat > "$STAGE/$NAME/INSTALL.txt" <<'TXT'
Live Clip Envelopes — install
=============================

1. Drag "Live Envelopes.app" into /Applications.

2. FIRST LAUNCH -- macOS blocks it once, because this app is signed but not
   notarized by Apple (notarization needs a paid Apple developer account).

   FASTEST FIX -- one line in Terminal, then it just opens, now and forever:

       xattr -dr com.apple.quarantine "/Applications/Live Envelopes.app"

   That deletes the "downloaded from the internet" flag macOS attaches. Gatekeeper
   only blocks flagged files, so with it gone the app opens on a normal double-click.
   Nothing else about your Mac's security changes.

   NO-TERMINAL FIX -- if you would rather not paste commands:

       a. Double-click the app. macOS refuses: "Apple could not verify 'Live
          Envelopes' is free of malware...". Click Done.
       b. Open System Settings > Privacy & Security, scroll down to Security.
          It now says "Live Envelopes.app was blocked to protect your Mac".
       c. Click "Open Anyway", authenticate, then click "Open".

   Control-clicking the app and choosing Open does NOT work on macOS 15 (Sequoia) --
   Apple removed that shortcut. On macOS 14 and earlier it still does.

3. Open it and click any button. It will say it needs Accessibility permission and
   show a "Grant Access..." button -- that opens System Settings at the right place.
   This is required: the app works by driving Live's own interface.
   If "Live Envelopes" is already listed there but still refused, switch it OFF and
   ON again (after an update the old permission no longer matches the new build).

4. AbletonOSC -- needed for the transposition buttons (-48..+48) and for revealing
   the Envelopes box automatically. Envelope switching itself works without it.

   a. Get it:   https://github.com/ideoforms/AbletonOSC   (Code > Download ZIP)
   b. Put it at, named exactly "AbletonOSC":
          ~/Music/Ableton/User Library/Remote Scripts/AbletonOSC
   c. Copy this release's patch over it -- it adds the four endpoints used here:
          cp abletonosc-patch/view.py \
             ~/Music/Ableton/"User Library"/"Remote Scripts"/AbletonOSC/abletonosc/view.py
   d. In Live: Settings > Link, Tempo & MIDI > Control Surface > AbletonOSC
      (Input/Output can stay None.)
   e. Restart Live. Remote Scripts are only read at launch.
   f. Check it: in the app, click "..." > "Check Setup..." -- everything should be
      ticked. It prints the exact path it looked at.

   Only one copy of Live can run at a time: AbletonOSC binds UDP port 11000, and a
   second Live silently gets no OSC at all.

5. Optional extras -- both call the binary inside the app, so nothing else to install:
   - keyboard-maestro/*.kmmacros  double-click to import. No hot keys are assigned;
     add your own keys, MIDI notes or mouse buttons in Keyboard Maestro.
   - shortcuts/*.shortcut         double-click each to add it to Shortcuts.app.
   - bin/live-envelope            only if you want it on your PATH for terminal use.

Full documentation, including the AbletonOSC walkthrough:
    README.md  ("AbletonOSC setup")
    https://github.com/esaruoho/LiveClipEnvelopes

Support: https://ko-fi.com/esaruoho  ·  esaruoho@gmail.com
TXT

echo "==> Zipping"
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" "$NAME" -x '*.DS_Store')
rm -rf "$STAGE"

echo "==> $OUT"
ls -lh "$OUT" | awk '{print "    " $5}'
unzip -l "$OUT" | tail -3
