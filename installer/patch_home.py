"""Patch the TV's own LG Home files to load PearWebOS.

LG Home is proprietary, so PearWebOS ships none of it: `pear setup` copies
the few files below off your TV, this applies small exact edits to them, and
the results go back to your TV only.

The edits are data, in patches.json, so the TV can make them too when it
updates itself (tv/update.js). Every edit must match exactly once. A firmware
whose Home differs fails here, on your computer, and nothing is installed. An
edit marked optional is for a part some firmware lacks (webOS 6.5 has no
scroll indicator, say): skipped when absent, and still held to exactly one
match when present.
"""
import json
import os
import sys

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "patches.json"), encoding="utf-8") as _f:
    _SPEC = json.load(_f)

APP = _SPEC["app"]
# Pear's own files, each mounted over a file LG Home never loads (and so
# named after it inside Pear: PearHome uses the backdrop as RecentBG { })
PEAR_FILES = _SPEC["pear_files"]
PATCHES = _SPEC["patches"]

# the stock files `pear setup` needs from the TV
NEEDED = sorted(list(PATCHES) + list(PEAR_FILES))


def patch(rel, text):
    """One stock file with its edits made."""
    for edit in PATCHES[rel]:
        if edit.get("end"):
            cut = text.rstrip().rfind("}")
            if cut < 0:
                sys.exit(f"{rel}: no closing brace to insert before. Nothing was installed.")
            text = text[:cut] + edit["new"] + text[cut:]
            continue
        n = text.count(edit["old"])
        if n == 0 and edit.get("optional"):
            print(f"  ({rel}: one edit not needed on this firmware)")
            continue
        if n != 1:
            sys.exit(f"{rel}: this firmware's Home differs from the one Pear knows "
                     f"(expected 1 match, found {n}). Nothing was installed.")
        text = text.replace(edit["old"], edit["new"])
    return text


def build(stock, out, qml_dir, fill):
    """Write the patched files and Pear's own into out/, mirroring qml/."""
    for slot in PEAR_FILES:
        if not os.path.exists(os.path.join(stock, slot)):
            sys.exit(f"{slot}: not on this TV, so there is nowhere to mount Pear")
    for rel in PATCHES:
        with open(os.path.join(stock, rel), encoding="utf-8") as f:
            write(out, rel, patch(rel, f.read()))
    for slot, name in PEAR_FILES.items():
        with open(os.path.join(qml_dir, name), encoding="utf-8") as f:
            text = f.read()
        for key, value in fill.items():
            text = text.replace(f"@{key}@", value)
        write(out, slot, text)


def write(out, rel, text):
    dest = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
