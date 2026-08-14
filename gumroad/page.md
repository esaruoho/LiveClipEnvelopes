![LiveClipEnvelopes icon](icon)

# LiveClipEnvelopes

Ableton Live 8 let you jump straight to a clip's **Gain**, **Transposition** and
**Sample Offset** envelopes. Live 12 makes you dig through two dropdowns every
time. This puts it back on a single keypress.

![The Live Envelopes floating panel: nine transpose buttons and Prev / Gain / Transpose / Sample Offset / Next](panel)

[[BUY]]

## What you get

- **Two buttons reach all three envelopes.** One toggles Gain ↔ Transposition, the other Sample Offset ↔ Transposition. Bind them to two spare mouse buttons and stop hunting through menus.
- **Warp-mode aware.** Sample Offset only exists in Beats Warp Mode, so outside Beats the same button goes to Transposition instead of landing on a greyed-out entry that does nothing.
- **A floating panel.** Always-on-top, stays put across Spaces, nine octave-transpose buttons (−48 … +48) plus Prev / Gain / Transpose / Sample Offset / Next.
- **Works without stealing focus.** Live doesn't need to be the frontmost app, so it fires from anywhere.
- **Direct or toggling, your call.** Dedicated keys for Show Gain / Show Transposition / Show Sample Offset that land and stay, plus toggle versions for when one button has to reach two envelopes.
- **Your choice of trigger.** Keyboard Maestro macros (18, ready to import), Apple Shortcuts (18, signed), the panel app, or the CLI directly.
- **Link/Unlink** the displayed envelope, and pop the chooser menu open under your pointer.

## Requirements

- macOS, Ableton Live 12 (built against 12.4)
- [AbletonOSC](https://github.com/ideoforms/AbletonOSC) — free, one-time setup, walked through below and inside the app
- Accessibility permission, granted once, because it drives Live's own interface

## Setup, start to finish

The zip contains a prebuilt, code-signed app. No compiler, no Terminal, no admin password.

**1 · Install.** Drag `Live Envelopes.app` into `/Applications`.

macOS blocks it the first time — the app is signed but not notarized (that needs a paid
Apple developer account). **One line in Terminal fixes it for good:**

`xattr -dr com.apple.quarantine "/Applications/Live Envelopes.app"`

That removes the "downloaded from the internet" flag; Gatekeeper only blocks flagged files,
so the app then opens on a normal double-click. No system setting is changed.

Rather not touch Terminal? Double-click the app, click **Done**, then **System Settings ▸
Privacy & Security ▸** scroll to **Security ▸ Open Anyway ▸** authenticate **▸ Open**.
(Control-click ▸ Open no longer works on macOS 15 — Apple removed it.) The zip includes a
`READ ME FIRST` file with both routes.

**2 · Accessibility.** Click any button. The app tells you it needs permission and gives you
a **Grant Access…** button that opens System Settings at exactly the right pane. Nothing to
hunt for.

**3 · AbletonOSC.** Needed for the transposition buttons and for opening the Envelopes box
for you. *Envelope switching works without it* — so if you skip this, everything except
transposition still works.

- Download it: [AbletonOSC](https://github.com/ideoforms/AbletonOSC) → **Code ▸ Download ZIP**
- Put the folder, named exactly `AbletonOSC`, at `~/Music/Ableton/User Library/Remote Scripts/AbletonOSC`
- Copy the included `abletonosc-patch/view.py` over `AbletonOSC/abletonosc/view.py` — it adds the four endpoints this uses
- Restart Live (Remote Scripts load at launch — it will not appear before that)
- Then let the app finish it: **⋯ ▸ Check Setup… ▸ Show Me in Live** opens Live's Settings on the right tab and names the slot, or **Enable It for Me** sets it and verifies it by round-trip

**4 · Confirm.** In the app, **⋯ ▸ Check Setup…** reports permission, the AbletonOSC patch
and whether Live is running — each with a tick or a fix. Use it before a session rather than
wondering mid-session.

**5 · Optional triggers.** Double-click any `keyboard-maestro/*.kmmacros` or
`shortcuts/*.shortcut`. They call the binary *inside* the app, so there is nothing else to
install and nothing to keep in sync.

`INSTALL.txt` in the zip repeats all of this, and `README.md` has the long version with
troubleshooting.

## Honest limits

This switches *which* envelope is displayed, and sets a clip's transposition
value. It does **not** draw or clear envelope curve data, and it can't duplicate
an envelope's loop — Live's API exposes no handle for those, and I'd rather say
so here than have you find out after paying.

## Free and open source

LiveClipEnvelopes is MIT-licensed and the full source is on
[GitHub](https://github.com/esaruoho/LiveClipEnvelopes) — you can build it
yourself for nothing. Buying here gets you the prebuilt, code-signed app plus
every macro and Shortcut in one zip, and supports the work.

---

By Lackluster (Esa Ruoho) · [music](https://lackluster.bandcamp.com/) · [github](https://github.com/esaruoho)
