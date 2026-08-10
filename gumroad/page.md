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
- **Your choice of trigger.** Keyboard Maestro macros (15, ready to import), Apple Shortcuts (15, signed), the panel app, or the CLI directly.
- **Link/Unlink** the displayed envelope, and pop the chooser menu open under your pointer.

## Requirements

- macOS, Ableton Live 12 (built against 12.4)
- [AbletonOSC](https://github.com/ideoforms/AbletonOSC) (free) — for the transpose buttons
- Grants Accessibility permission once, because it drives Live's own interface

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
