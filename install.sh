#!/bin/bash
# Builds and installs:
#   - the live-envelope CLI to /usr/local/bin (needs sudo)
#   - the Live Envelopes.app floating panel to /Applications
#
# Usage: ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

CLI_DEST=/usr/local/bin/live-envelope
APP_DEST="/Applications/Live Envelopes.app"

echo "==> Building live-envelope CLI"
TMP_CLI=$(mktemp)
swiftc -O -o "$TMP_CLI" bin/live-envelope.swift
sudo mv "$TMP_CLI" "$CLI_DEST"
sudo chmod 755 "$CLI_DEST"
echo "    installed to $CLI_DEST"

echo "==> Building Live Envelopes.app"
rm -rf "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS" "$APP_DEST/Contents/Resources"
swiftc -O -o "$APP_DEST/Contents/MacOS/LiveEnvelopePanel" LiveEnvelopePanel/main.swift
cp LiveEnvelopePanel/AppIcon.icns "$APP_DEST/Contents/Resources/AppIcon.icns"
cat > "$APP_DEST/Contents/Info.plist" <<'PLIST'
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

#--------------------------------------------------------------------------------
# Sign with a real local identity if one exists, not ad-hoc. This matters
# specifically for Accessibility: the panel is the "responsible process" for the
# live-envelope child process it spawns, so macOS ties the Accessibility grant to
# the panel's code identity. Ad-hoc signing embeds a hash of the exact binary, so
# every rebuild produces a new identity and re-triggers the Accessibility prompt.
# A certificate-backed signature keeps the same identity across rebuilds.
#--------------------------------------------------------------------------------
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | rg -o '"[^"]+"' | head -1 | tr -d '"' || true)
if [ -n "$IDENTITY" ]; then
    echo "    signing with $IDENTITY"
    codesign --force --deep -s "$IDENTITY" "$APP_DEST"
else
    echo "    no code-signing identity found -- signing ad-hoc."
    echo "    NOTE: ad-hoc signing means every rebuild will re-trigger the macOS"
    echo "    Accessibility permission prompt for this app. To avoid that, create a"
    echo "    local code-signing certificate (Keychain Access > Certificate Assistant"
    echo "    > Create a Certificate, type: Code Signing) and re-run this script."
    codesign --force --deep -s - "$APP_DEST"
fi

touch "$APP_DEST"
echo "    installed to $APP_DEST"

read -p "==> Pin Live Envelopes.app to the Dock? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    defaults write com.apple.dock persistent-apps -array-add \
        "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_DEST</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock
    echo "    pinned"
fi

cat <<'EOF'

==> Done.

Next steps:
  1. Open "Live Envelopes.app" (Dock, or /Applications) and click any button once.
     macOS will ask you to grant it Accessibility access -- required once, in
     System Settings > Privacy & Security > Accessibility.
  2. Apply the AbletonOSC patch (see README.md) so Live can show/hide the
     Envelopes box and set clip transposition over OSC.
  3. Optionally import keyboard-maestro/*.kmmacros or double-click any file in
     shortcuts/signed/ to add the equivalent Keyboard Maestro macro / Shortcut.
EOF
