<img src="docs/icon.png" width="96" align="right" alt="">

# LiveClipEnvelopes

Restores Ableton Live 8's "quick chooser" workflow for a clip's Gain,
Transposition, and Sample Offset envelopes — as keyboard shortcuts, a floating
button panel, Keyboard Maestro macros, or Apple Shortcuts. macOS only.

![The Live Envelopes panel](docs/panel.png)

Live 12 has no exposed API for selecting which clip envelope is displayed (see
[How it works](#how-it-works)), so this drives Live's actual UI through the
Accessibility API instead: it presses the same Device/Control Chooser popups and
Link/Unlink button you would click by hand. Nothing here writes envelope curve
data — only *which envelope is shown* changes, plus (optionally) the clip's own
transposition value via [AbletonOSC](https://github.com/ideoforms/AbletonOSC).

## What's here

| Piece | What it does |
|---|---|
| `bin/live-envelope.swift` | The core CLI. Everything else just shells out to this. |
| `LiveEnvelopePanel/` | A floating, Dock-launchable button panel (`Live Envelopes.app`). |
| `abletonosc-patch/` | Three small AbletonOSC endpoints this needs (see below). |
| `keyboard-maestro/` | One `.kmmacros` file with all 15 commands, no triggers assigned. |
| `shortcuts/signed/` | The same 15 commands as importable Apple Shortcuts. |
| `scripts/generate-automations.py` | Regenerates the two above from one command list. |
| `package.sh` | Builds the distributable zip (app + CLI + patch + macros + Shortcuts). |
| `gumroad/` | The store page: copy in `page.md`, `./gumroad/deploy.sh` renders and publishes it. |

## Install

```bash
git clone https://github.com/esaruoho/LiveClipEnvelopes
cd LiveClipEnvelopes
./install.sh
```

This builds and installs the CLI to `/usr/local/bin/live-envelope` (asks for
`sudo`) and the panel app to `/Applications/Live Envelopes.app`, offering to pin
it to the Dock. It signs the app with a local code-signing identity if one
exists in your keychain, rather than ad-hoc — see [Accessibility and rebuilding](#accessibility-and-rebuilding)
for why that matters.

Then apply the AbletonOSC patch (only needed for `open`'s auto-reveal fallback
and the transpose commands — see [AbletonOSC endpoints](#abletonosc-endpoints)):

```bash
cp abletonosc-patch/view.py /path/to/AbletonOSC/abletonosc/view.py
# reload from Live: send an OSC message to /live/api/reload, or restart Live
```

## Usage

```
live-envelope <command>

  gain                                    toggle Gain <-> Transposition
  smart | sample offset | transposition   Beats: toggle the two; else Transposition
  transpose-up-12 | transpose-down-12     snap the clip's transposition by an octave
  transpose-set-<n>                       set transposition to an absolute value
                                           (n may be "neg24" etc. -- shells don't
                                           like a bare "-" inside one argument)
  exact <name>                            select <name> verbatim, no substitution
  next | prev                             cycle only what the warp mode offers
  link | unlink | toggle-link             Link/Unlink the displayed envelope
  open                                    pop the chooser menu open (press again to close)
  open-at-mouse                           ... and move it under the pointer
  status                                  print the current chooser state
  list                                    list every entry the chooser offers
```

`gain` and `sample offset` are both toggles, designed to live on two physical
buttons (a mouse's extra buttons, say): `gain` alternates Gain ↔ Transposition;
`sample offset` alternates Sample Offset ↔ Transposition in Beats Warp Mode, and
just selects Transposition in every other mode (Sample Offset doesn't exist
outside Beats). Between them, two buttons reach all three envelopes.

Every command that changes the selection first asks Live to show the Envelopes
box if it's hidden, and switches the Device Chooser to "Clip" if it wasn't
already there — so it works from a clean Sample-tab view, not just when the
Envelopes box is already visible on the right envelope.

### The floating panel

`Live Envelopes.app` — nine transpose buttons (-48 to +48) plus Prev / Gain /
Transpose / Sample Offset / Next, each just running `live-envelope`. The title
bar doubles as a result/error readout: it flashes the command's result (or an
error, held longer) and reverts to "Live Clip Envelopes" after a couple of
seconds.

### Keyboard Maestro / Shortcuts

Both `keyboard-maestro/Live Clip Envelopes.kmmacros` and every file in
`shortcuts/signed/` reference `/usr/local/bin/live-envelope` — the path
`install.sh` uses. If you installed the CLI somewhere else, edit the one
`Execute Shell Script` action (KM) or `Run Shell Script` action (Shortcuts)
inside each.

Neither file assigns a trigger — import them and assign your own hot keys, MIDI
notes, mouse buttons, or run them from Shortcuts' menu bar item / Siri.

To regenerate both from scratch (e.g. after adding a command):

```bash
python3 scripts/generate-automations.py
```

## How it works

Live's `Clip.View` exposes exactly `show_envelope()`, `hide_envelope()`, and
`select_envelope_parameter()` — and that last one requires a
`TPyHandle<ATimeableValue>`, a handle Live's Python API never hands out for a
clip's own Gain / Transposition / Sample Offset ("warper") parameters. They're
plain floats (`clip.gain`, `clip.pitch_coarse`) with no wrapper object anywhere
in the API. `create_automation_envelope()` wants the identical handle, so
there's no way to read or write the actual envelope *curve* either — confirmed
directly against the API, not inferred:

```
Boost.Python.ArgumentError: Python argument types in
    Clip.create_automation_envelope(Clip, float)
did not match C++ signature:
    create_automation_envelope(TPyHandle<AClip>, TPyHandle<ATimeableValue>)
```

So this tool doesn't touch the API for selection at all. It walks Live's
accessibility tree (bounded by depth and node count, and geometrically pruned to
the Envelopes box's screen region — full search takes minutes on a large Set) to
find the **Device Chooser**, **Control Chooser**, and **Link/Unlink Envelope**
controls, and presses them the way you would. Two quirks of Live's
implementation shape the code:

- The choosers' `AXValue` is read-only, so selecting an entry means opening the
  menu and pressing the item, not setting a value directly.
- Pressing a chooser **toggles** its menu open/closed rather than just opening
  it — press again to close.

## First launch on someone else's Mac

The app is signed with a certificate but **not notarized by Apple** (notarization requires
the $99/year Apple Developer Program), so macOS blocks it once on any machine it wasn't built
on. `spctl -a` reports `rejected`, which is expected for a non-notarized build.

**One line fixes it permanently.** Move the app to `/Applications`, then:

```sh
xattr -dr com.apple.quarantine "/Applications/Live Envelopes.app"
```

macOS attaches a `com.apple.quarantine` attribute to anything a browser downloads, and
Gatekeeper only blocks attributed files. Removing it from this one bundle makes the app open
on a normal double-click, changes no system setting, and affects nothing else. `-r` matters:
the embedded `live-envelope` binary carries the attribute too.

**Without Terminal**, on macOS 15 (Sequoia) and later:

1. Double-click the app; macOS refuses with *"Apple could not verify…"*. Click **Done**.
2. **System Settings ▸ Privacy & Security**, scroll to **Security**: *"Live Envelopes.app was
   blocked to protect your Mac"* ▸ **Open Anyway** ▸ authenticate ▸ **Open**.

Apple removed the Control-click ▸ Open bypass in macOS 15; on macOS 14 and earlier it still
works.

**Why not just ship a helper app that opens the right Settings pane?** Because that helper
would be unsigned and unnotarized too, so it would be blocked by the very check it exists to
get past. The quarantine command above is the only fix that needs no privileged app.

## AbletonOSC setup

Live Clip Envelopes works by driving Live's own interface through macOS Accessibility, so
**switching between Gain / Transposition / Sample Offset needs nothing but the app itself.**
AbletonOSC is needed for exactly two things:

- the **transposition buttons** (`-48 … +48`, and the ↑/↓ arrow keys), which write the
  clip's real transposition value; and
- **revealing the Envelopes box** automatically when it is hidden, because that tab is not
  exposed to Accessibility.

Without AbletonOSC the app still switches envelopes — as long as the Envelopes box is
already open — and the transpose buttons do nothing. The app tells you which state you are
in: **⋯ ▸ Check Setup…**

### 1. Download AbletonOSC

<https://github.com/ideoforms/AbletonOSC> → **Code ▸ Download ZIP**, or:

```sh
git clone https://github.com/ideoforms/AbletonOSC
```

### 2. Put it where Live looks for Remote Scripts

The folder must be named `AbletonOSC` and sit here (create `Remote Scripts` if missing):

```
~/Music/Ableton/User Library/Remote Scripts/AbletonOSC
```

```sh
mkdir -p ~/Music/Ableton/"User Library"/"Remote Scripts"
mv ~/Downloads/AbletonOSC-master ~/Music/Ableton/"User Library"/"Remote Scripts"/AbletonOSC
```

That location is shared by every installed Live version, so this is done once.

### 3. Apply the patch that adds the four endpoints

This project needs four endpoints that upstream AbletonOSC does not have yet. The release
zip ships a ready-made `view.py`; copy it over the one in AbletonOSC:

```sh
cp abletonosc-patch/view.py \
   ~/Music/Ableton/"User Library"/"Remote Scripts"/AbletonOSC/abletonosc/view.py
```

Or, inside a git clone of AbletonOSC:

```sh
git apply /path/to/abletonosc-patch/clip-envelope-endpoints.patch
```

The endpoints added are `/live/view/show_clip_envelope`, `/live/view/hide_clip_envelope`,
`/live/view/nudge_clip_transposition` and `/live/view/set_clip_transposition`.

### 4. Turn it on in Live

**The app can do this part for you.** In Live Clip Envelopes: **⋯ ▸ Check Setup…** then either

- **Show Me in Live** — opens Live's Settings on the Tempo & MIDI tab and names the exact
  Control Surface slot to change, without touching your configuration; or
- **Enable It for Me** — selects AbletonOSC in the first free slot and then verifies it by
  round-tripping an OSC message, so you get a yes/no rather than a hopeful message.

By hand it is **Live ▸ Settings ▸ Link, Tempo & MIDI ▸ Control Surface**, pick **AbletonOSC**.
Input and Output can stay `None` — it listens on UDP, not MIDI.

From the command line the same three things are:

    live-envelope abletonosc probe     is it loaded and answering?
    live-envelope abletonosc guide     open Settings at the right slot, change nothing
    live-envelope abletonosc enable    select it, then verify by round-trip

Live exposes each Control Surface slot to Accessibility as `Remote Script <n> Type`, which is
how this works at all — the same kind of control the envelope chooser is.

### 5. Restart Live

Live loads Remote Scripts at launch, so a restart is required after installing or patching.

### 6. Check it worked

In Live Clip Envelopes: **⋯ ▸ Check Setup…** — AbletonOSC should show a ✓. Live's own log
also records it:

```
info: Python: INFO:abletonosc: Started AbletonOSC on address ('0.0.0.0', 11000)
```

found at `~/Library/Preferences/Ableton/Live <version>/Log.txt`.

### If it does not work

- **Only one Live at a time.** AbletonOSC binds UDP port 11000; a second Live cannot, and
  the second one silently gets no OSC at all.
- **Re-check the folder name.** It must be exactly `AbletonOSC`, containing an `abletonosc`
  subfolder — not `AbletonOSC-master`.
- **Patch went to the wrong copy.** If you have several AbletonOSC folders, the one that
  matters is the one under `User Library/Remote Scripts`. **⋯ ▸ Check Setup…** prints the
  exact path it inspected.

## AbletonOSC endpoints

Three small additions, none touching envelope content:

| Endpoint | Purpose |
|---|---|
| `/live/view/show_clip_envelope` | Used as a fallback when the Envelopes box isn't visible at all (only `Clip.View` calls, not accessibility). |
| `/live/view/nudge_clip_transposition` | Adds a signed semitone delta to the displayed clip's `pitch_coarse`, clamped to -48..48. Backs `transpose-up-12` / `-down-12`. |
| `/live/view/set_clip_transposition` | Sets `pitch_coarse` to an absolute value. Backs `transpose-set-<n>`. |

**Caveat, stated plainly:** these three write the clip's *scalar* transposition
value. If a Transposition envelope curve is already drawn on the clip, the drawn
curve still determines playback — Live's API has no way to clear a single warp
parameter's envelope (only `clip.clear_all_envelopes()`, which removes every
envelope on the clip, including unrelated ones, so this tool never calls it).

## What this can't do

- **Edit envelope curve content** (draw/clear breakpoints for Gain/Transposition/
  Sample Offset) — no API path exists, as shown above. The only remaining route
  is simulating actual mouse drags on the drawn curve, which is a different,
  much more fragile kind of automation than anything else here and isn't
  implemented.
- **Duplicate an envelope's loop + content** (Live's own Cmd-D behavior) — the
  Python `duplicate_loop()` method exists but errors "only available for Midi
  clips" on an audio clip. No menu item reaches the same operation either
  (`Select Loop` + `Duplicate Time` was tested and does nothing to the clip's
  loop bounds). The Position/Length sliders for an *unlinked* envelope's own
  loop region are visible to accessibility but report `settable=false`
  (drag-only).

## Requirements

- macOS, Ableton Live 12 (built and tested against 12.4.x)
- [AbletonOSC](https://github.com/ideoforms/AbletonOSC) installed as a Live
  Control Surface, for the transpose commands and the `open` auto-reveal
  fallback
- Accessibility permission for `live-envelope` (granted per-process; a Dock
  app spawning it as a child, like the panel here, needs its own grant — see
  below)
- Xcode Command Line Tools (`swiftc`) to build

## Accessibility and rebuilding

If you edit and rebuild the panel app, macOS may ask you to re-grant
Accessibility access every single time — this happens with **ad-hoc** code
signing (`codesign -s -`), which embeds a hash of the exact binary bytes in its
designated requirement, so every rebuild is a new identity as far as TCC is
concerned. Signing with a real (even self-issued, non-Apple-notarized)
certificate fixes this, because the identity then depends on the certificate,
not the binary content — verified empirically while building this: rebuilding
and re-signing with the same certificate did not re-trigger the prompt.
`install.sh` does this automatically if it finds a codesigning identity in your
keychain (Keychain Access → Certificate Assistant → Create a Certificate →
type "Code Signing" is enough).

This matters specifically for the panel app because it never calls an
Accessibility API itself — only the `live-envelope` child process it spawns
does — and macOS attributes that permission check to the panel as the
"responsible process."

## Prebuilt download

The source here is complete and MIT-licensed — `./install.sh` builds everything
from scratch for free. If you'd rather skip the build, a prebuilt, code-signed
bundle (app + CLI + all macros and Shortcuts + install notes, one zip) is on
Gumroad for €10, which also funds the work:

**https://lackluster.gumroad.com/l/liveclipenvelopes**

Build it yourself or buy it — both are fine.

## Support

If you find this tool useful:
- [Ko-Fi](https://ko-fi.com/esaruoho)
- [BuyMeACoffee](https://buymeacoffee.com/esaruoho)
- [PayPal](https://www.paypal.me/esaruoho)
- [GitHub Sponsors](https://github.com/sponsors/esaruoho)
- [Patreon](http://patreon.com/esaruoho)
- [Bandcamp](http://lackluster.bandcamp.com/)

## Credits

Created by Lackluster (esaruoho)

Built on top of [AbletonOSC](https://github.com/ideoforms/AbletonOSC) by Daniel Jones.

## License

MIT — see [LICENSE](LICENSE).
