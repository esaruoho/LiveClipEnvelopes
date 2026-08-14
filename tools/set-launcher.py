#!/usr/bin/env python3
"""
Point every Keyboard Maestro macro and every Shortcut at the ONE live-envelope binary
that ships inside Live Envelopes.app.

Why: the CLI used to be installed separately (/usr/local/bin, ~/.local/bin, a dev
checkout...) and each macro probed a list of paths. That meant several copies of the
same binary on one machine, each with its own code signature and therefore its own
Accessibility grant, and whichever copy came first in the probe order won — so a stale
copy could silently keep being the one that ran. One binary inside the app bundle has
one identity, one permission, and no way to go stale.

Run after changing the launcher, or after adding a macro/shortcut:

    python3 tools/set-launcher.py            # rewrite in place
    python3 tools/set-launcher.py --check    # report only, exit 1 if anything is stale

Touches:
    keyboard-maestro/*.kmmacros      (plist: Macros[].Actions[].Text)
    shortcuts/unsigned/*.wflow       (plist: WFWorkflowActions[].WFWorkflowActionParameters.Script)
"""

import plistlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

#--------------------------------------------------------------------------------
# The launcher. Both /Applications and ~/Applications are checked because macOS lets
# an app live in either. Kept POSIX-compatible: Keyboard Maestro runs this under sh,
# the Shortcuts actions run it under zsh.
#--------------------------------------------------------------------------------
LAUNCHER = '''# Runs the live-envelope CLI that ships inside Live Envelopes.app — the single copy.
APP="/Applications/Live Envelopes.app/Contents/MacOS/live-envelope"
[ -x "$APP" ] || APP="$HOME/Applications/Live Envelopes.app/Contents/MacOS/live-envelope"
[ -x "$APP" ] || {{
  osascript -e 'display notification "Live Envelopes.app not found — put it in /Applications" with title "Live Clip Envelopes"' >/dev/null 2>&1
  exit 1
}}
exec "$APP" {args}'''

# Pulls the arguments out of either the old probe-loop form or the current one.
ARG_PATTERNS = [
    re.compile(r'\[ -x "\$p" \] && exec "\$p" (.+)$', re.M),   # old: for p in ...; do
    re.compile(r'^exec "\$APP" (.+)$', re.M),                  # current
]


def extract_args(script: str):
    for pattern in ARG_PATTERNS:
        found = pattern.search(script)
        if found:
            return found.group(1).strip()
    return None


def rewrite(script: str):
    """Returns (new_script, args) or (None, None) if the args could not be found."""
    args = extract_args(script)
    if args is None:
        return None, None
    return LAUNCHER.format(args=args), args


def process_kmmacros(path: Path, check: bool):
    data = plistlib.loads(path.read_bytes())
    groups = data if isinstance(data, list) else [data]
    changed, stale = 0, []
    for group in groups:
        for macro in group.get("Macros", []):
            for action in macro.get("Actions", []):
                script = action.get("Text")
                if not script or "live-envelope" not in script:
                    continue
                new, args = rewrite(script)
                if new is None:
                    stale.append(f"{macro.get('Name')}: could not find the command")
                    continue
                if new != script:
                    stale.append(f"{macro.get('Name')} -> {args}")
                    action["Text"] = new
                    changed += 1
    if changed and not check:
        with path.open("wb") as handle:
            plistlib.dump(data, handle)
    return changed, stale


def process_wflow(path: Path, check: bool):
    data = plistlib.loads(path.read_bytes())
    changed, stale = 0, []
    for action in data.get("WFWorkflowActions", []):
        params = action.get("WFWorkflowActionParameters", {})
        script = params.get("Script")
        if not script or "live-envelope" not in script:
            continue
        new, args = rewrite(script)
        if new is None:
            stale.append(f"{path.name}: could not find the command")
            continue
        if new != script:
            stale.append(f"{path.stem} -> {args}")
            params["Script"] = new
            changed += 1
    if changed and not check:
        with path.open("wb") as handle:
            plistlib.dump(data, handle)
    return changed, stale


def main():
    check = "--check" in sys.argv
    total, report = 0, []

    for path in sorted((REPO / "keyboard-maestro").glob("*.kmmacros")):
        count, notes = process_kmmacros(path, check)
        total += count
        if notes:
            report.append((path.relative_to(REPO), notes))

    unsigned = REPO / "shortcuts" / "unsigned"
    for path in sorted(unsigned.glob("*.wflow")) if unsigned.is_dir() else []:
        count, notes = process_wflow(path, check)
        total += count
        if notes:
            report.append((path.relative_to(REPO), notes))

    for where, notes in report:
        print(f"{where}")
        for note in notes:
            print(f"    {note}")

    verb = "would update" if check else "updated"
    print(f"\n{verb} {total} action(s)")
    if check and total:
        sys.exit(1)


if __name__ == "__main__":
    main()
