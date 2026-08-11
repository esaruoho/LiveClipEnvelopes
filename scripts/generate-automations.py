#!/usr/bin/env python3
"""
Generates the Keyboard Maestro macro group and the full set of Apple Shortcuts
from one canonical command list, so the two stay in sync.

Usage:
    python3 scripts/generate-automations.py

Requires the `shortcuts` CLI (macOS 12+) to sign the generated .shortcut files.
Writes:
    keyboard-maestro/Live Clip Envelopes.kmmacros
    shortcuts/unsigned/*.wflow   (intermediate, not needed after signing)
    shortcuts/signed/*.shortcut  (double-click to import)
"""
import datetime
import pathlib
import plistlib
import subprocess
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent


def script_for(args: str) -> str:
    """
    The shell body for one command.

    Deliberately does NOT hardcode a single path. `install.sh` puts the binary in
    /usr/local/bin, but a Homebrew-style prefix or a dev checkout are both normal,
    and a macro that points at one absent path fails *silently* — these actions run
    with DisplayKind None, so nothing surfaces. So: try the known locations, and if
    none exists, raise a real macOS notification instead of dying quietly.
    """
    return (
        'for p in "/usr/local/bin/live-envelope" "/opt/homebrew/bin/live-envelope" '
        '"$HOME/.local/bin/live-envelope" "$HOME/work/apple/bin/live-envelope"; do\n'
        f'  [ -x "$p" ] && exec "$p" {args}\n'
        'done\n'
        "osascript -e 'display notification \"live-envelope not found — run install.sh\" "
        "with title \"LiveClipEnvelopes\"' >/dev/null 2>&1\n"
        'exit 1'
    )


# (Shortcut/macro display name, live-envelope arguments)
COMMANDS = [
    #--------------------------------------------------------------------------------
    # Direct selects. These always land on the named envelope and stay there, which
    # is what you want on a dedicated key. The toggles below are for the two-button
    # mouse workflow, where one button has to reach more than one envelope.
    #--------------------------------------------------------------------------------
    ("Live Clip: Show Gain",            "exact Gain"),
    ("Live Clip: Show Transposition",   "exact Transposition"),
    ("Live Clip: Show Sample Offset",   "exact Sample Offset"),
    # Toggles
    ("Live Clip: Gain (toggle)",        "gain"),
    ("Live Clip: Sample Offset (toggle)", "sample offset"),
    ("Live Clip: Next Envelope",        "next"),
    ("Live Clip: Prev Envelope",        "prev"),
    ("Live Clip: Toggle Link",          "toggle-link"),
    ("Live Clip: Open Envelope Menu",   "open"),
    ("Live Clip Transpose: -48",        "transpose-set-neg48"),
    ("Live Clip Transpose: -36",        "transpose-set-neg36"),
    ("Live Clip Transpose: -24",        "transpose-set-neg24"),
    ("Live Clip Transpose: -12",        "transpose-down-12"),
    ("Live Clip Transpose: 0",          "transpose-set-0"),
    ("Live Clip Transpose: +12",        "transpose-up-12"),
    ("Live Clip Transpose: +24",        "transpose-set-24"),
    ("Live Clip Transpose: +36",        "transpose-set-36"),
    ("Live Clip Transpose: +48",        "transpose-set-48"),
]


def build_kmmacros():
    now = (datetime.datetime.now() - datetime.datetime(2001, 1, 1)).total_seconds()

    def action(command, uid):
        return {
            "ActionUID": uid,
            "DisplayKind": "None",
            "HonourFailureSettings": True,
            "IncludeStdErr": False,
            "MacroActionType": "ExecuteShellScript",
            "Path": "",
            "Source": "Nothing",
            "Text": script_for(command),
            "TimeOutAbortsMacro": True,
            "TrimResults": True,
            "TrimResultsNew": True,
            "UseText": True,
        }

    macros = []
    for index, (name, command) in enumerate(COMMANDS):
        macros.append({
            "Actions": [action(command, 9000 + index)],
            "CreationDate": now,
            "ModificationDate": now,
            "Name": name,
            "Triggers": [],  # left empty on purpose -- assign your own hot keys / MIDI / mouse buttons
            "UID": str(uuid.uuid4()).upper(),
        })

    group = [{
        "Activate": "Normal",
        "AddToMacroPalette": False,
        "AddToStatusMenu": False,
        "CreationDate": now,
        "DisplayToggle": False,
        "IsActive": True,
        "KeyCode": 32767,
        "Macros": macros,
        "Modifiers": 0,
        "Name": "Live Clip Envelopes",
        "ToggleMacroUID": str(uuid.uuid4()).upper(),
        "UID": str(uuid.uuid4()).upper(),
    }]

    out = ROOT / "keyboard-maestro" / "Live Clip Envelopes.kmmacros"
    out.write_bytes(plistlib.dumps(group, fmt=plistlib.FMT_XML))
    print("wrote", out)


def make_wflow(name, args):
    return {
        "WFWorkflowActions": [{
            "WFWorkflowActionIdentifier": "is.workflow.actions.runshellscript",
            "WFWorkflowActionParameters": {
                "Script": script_for(args),
                "Shell": "/bin/zsh",
                "Input": "",
                "WFShellScriptInputPassthrough": False,
            },
        }],
        "WFWorkflowClientVersion": "1200",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": 431817727,
            "WFWorkflowIconGlyphNumber": 59511,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [
            "WFAppStoreAppContentItem", "WFArticleContentItem", "WFContactContentItem",
            "WFDateContentItem", "WFEmailAddressContentItem", "WFFolderContentItem",
            "WFGenericFileContentItem", "WFImageContentItem", "WFiTunesProductContentItem",
            "WFLocationContentItem", "WFDCMapsLinkContentItem", "WFAVAssetContentItem",
            "WFPDFContentItem", "WFPhoneNumberContentItem", "WFRichTextContentItem",
            "WFSafariWebPageContentItem", "WFStringContentItem", "WFURLContentItem",
        ],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": ["NCWidget", "WatchKit"],
        "WFWorkflowName": name,
    }


def build_shortcuts():
    unsigned_dir = ROOT / "shortcuts" / "unsigned"
    signed_dir = ROOT / "shortcuts" / "signed"
    unsigned_dir.mkdir(parents=True, exist_ok=True)
    signed_dir.mkdir(parents=True, exist_ok=True)

    for name, args in COMMANDS:
        unsigned = unsigned_dir / f"{name}.wflow"
        signed = signed_dir / f"{name}.shortcut"
        unsigned.write_bytes(plistlib.dumps(make_wflow(name, args), fmt=plistlib.FMT_XML))
        result = subprocess.run(
            ["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print("FAILED to sign", name, ":", result.stderr)
        else:
            print("wrote", signed)


if __name__ == "__main__":
    build_kmmacros()
    build_shortcuts()
