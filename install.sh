#!/bin/bash
# Builds and installs Live Envelopes.app to /Applications, with the live-envelope CLI
# embedded inside the bundle. That embedded binary is the ONE copy: the app runs it, and
# the Keyboard Maestro macros and Shortcuts call it at
#   /Applications/Live Envelopes.app/Contents/MacOS/live-envelope
# so there is nothing to keep in sync and nothing that can go stale. No sudo needed.
#
# Usage: ./install.sh [--app-only] [--with-cli]
set -euo pipefail
cd "$(dirname "$0")"

#--------------------------------------------------------------------------------
# --app-only rebuilds and signs just the .app, skipping the /usr/local/bin copy.
# That copy is the only step needing sudo, so --app-only runs unattended — which is
# what makes it possible to rebuild the app without reaching for swiftc by hand and
# accidentally stripping the code signature (which breaks the Accessibility grant).
# The CLI is still built and embedded in the bundle either way.
#--------------------------------------------------------------------------------
APP_ONLY=0
WITH_CLI=0
WITH_ARROWS=0
for arg in "$@"; do
    case "$arg" in
        --app-only) APP_ONLY=1 ;;
        --with-cli) WITH_CLI=1 ;;
        --with-arrows) WITH_ARROWS=1 ;;
        -h|--help)
            sed -n '2,8p' "$0"
            echo "  --app-only   rebuild+sign the app only"
            echo "  --with-cli    ALSO put live-envelope on your PATH, for use in a terminal"
            echo "  --with-arrows build the optional hover-gated arrow-key daemon (see bin/live-arrows)"
            exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

APP_DEST="/Applications/Live Envelopes.app"

echo "==> Building live-envelope CLI"
TMP_CLI=$(mktemp)
swiftc -O -o "$TMP_CLI" bin/live-envelope.swift
echo "    built (it gets embedded in the app below)"

#--------------------------------------------------------------------------------
# Putting a copy on PATH is now opt-in and purely a convenience for terminal use. The
# macros and Shortcuts no longer look for it: they call the copy inside the bundle, so
# there is exactly one binary, one code signature and one Accessibility grant. Several
# copies on one machine is what previously let a stale build silently win the probe.
#--------------------------------------------------------------------------------
if [ "$WITH_CLI" -eq 1 ] && [ "$APP_ONLY" -eq 0 ]; then
    if [ -w /usr/local/bin ]; then
        CLI_DEST=/usr/local/bin/live-envelope
    elif sudo -n true 2>/dev/null; then
        CLI_DEST=/usr/local/bin/live-envelope
        sudo cp "$TMP_CLI" "$CLI_DEST" && sudo chmod 755 "$CLI_DEST"
        echo "    also installed to $CLI_DEST"
        CLI_DEST=""
    else
        CLI_DEST="$HOME/.local/bin/live-envelope"
        mkdir -p "$HOME/.local/bin"
    fi
    if [ -n "${CLI_DEST:-}" ]; then
        cp "$TMP_CLI" "$CLI_DEST"
        chmod 755 "$CLI_DEST"
        echo "    also installed to $CLI_DEST"
    fi
fi

#--------------------------------------------------------------------------------
# Optional extra, not part of the shipped app: a CGEventTap daemon that gives the
# Envelopes chooser hover-gated arrow keys inside Live. It needs its own Accessibility
# grant and runs as a background process, so it is opt-in and lives next to its source.
#--------------------------------------------------------------------------------
if [ "$WITH_ARROWS" -eq 1 ]; then
    echo "==> Building live-envelope-arrows (optional)"
    swiftc -O -o bin/live-envelope-arrows bin/live-envelope-arrows.swift
    echo "    built bin/live-envelope-arrows — start it with: bin/live-arrows start"
fi

echo "==> Building Live Envelopes.app"
rm -rf "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS" "$APP_DEST/Contents/Resources"
swiftc -O -o "$APP_DEST/Contents/MacOS/LiveEnvelopePanel" LiveEnvelopePanel/main.swift
cp LiveEnvelopePanel/AppIcon.icns "$APP_DEST/Contents/Resources/AppIcon.icns"
# Help reads this from inside the bundle, so it works with no network.
cp README.md "$APP_DEST/Contents/Resources/README.md"

# Embed the CLI so it is signed with the app and covered by the app's permission.
cp "$TMP_CLI" "$APP_DEST/Contents/MacOS/live-envelope"
chmod 755 "$APP_DEST/Contents/MacOS/live-envelope"
rm -f "$TMP_CLI"
echo "    embedded live-envelope in the app bundle"
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
#--------------------------------------------------------------------------------
# Extract the identity with sed, not ripgrep. Two reasons, both of which silently
# produced an ad-hoc build before:
#   - ripgrep is not installed on a normal user's machine at all.
#   - even where it is, `security find-identity` output trips its binary detection,
#     so `rg -o` prints nothing at all without -a, leaving IDENTITY empty.
# Prefer a Developer ID (distributable) over an Apple Development cert if both exist.
#--------------------------------------------------------------------------------
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' || true)
IDENTITY=$(printf '%s\n' "$IDENTITIES" | grep -m1 '^Developer ID Application' || true)
[ -n "$IDENTITY" ] || IDENTITY=$(printf '%s\n' "$IDENTITIES" | grep -m1 . || true)

if [ -n "$IDENTITY" ]; then
    echo "    signing with $IDENTITY"
    #--------------------------------------------------------------------------------
    # Pin the signing identifier to the bundle id. Left to itself the linker names it
    # "LiveEnvelopePanel", which does not match the CFBundleIdentifier that TCC keys
    # the Accessibility grant on.
    #--------------------------------------------------------------------------------
    codesign --force --deep --identifier com.esaruoho.LiveEnvelopePanel \
             -s "$IDENTITY" "$APP_DEST"
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

if [ -t 0 ] && [ "$APP_ONLY" -eq 0 ]; then
    read -p "==> Pin Live Envelopes.app to the Dock? [y/N] " -n 1 -r
    echo
else
    REPLY=n
fi
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
     The app checks this for you: "Live Clip Envelopes > Check Setup..." reports
     permission, the CLI, the AbletonOSC patch and whether Live is running, and
     warns on the panel itself if anything is missing.
  3. Optionally import keyboard-maestro/*.kmmacros or double-click any file in
     shortcuts/signed/ to add the equivalent Keyboard Maestro macro / Shortcut.
EOF
