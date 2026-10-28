#!/usr/bin/env python3
"""FORT 9000 for Forts - copy the mod from the dev folder into the folder that is uploaded to the Workshop.

The git repo and the mod used for development live in data/mods/fort9000dev ("FORT 9000 AI DEV" in game).
The published mod is data/mods/fort9000 ("FORT 9000 AI"). This script:
  1. checks the dev mod (no .bat/.cmd/.exe, no Probe switched on, Force empty),
  2. empties the target folder, except publishedfileid.lua (written by the game after the first upload),
  3. copies every root entry that does not start with "." (dot folders are development only),
  4. rewrites mods/fort9000dev/ to mods/fort9000/ in the .lua files and drops " DEV" from displayname.lua,
  5. keeps a copy of publishedfileid.lua in .dev/ (tracked in git) and restores it when the target has none.

Usage:
  python .dev/tools/publish.py              -> publish into ../fort9000
  python .dev/tools/publish.py --dry-run    -> only check and list what would be copied
  python .dev/tools/publish.py --target DIR -> publish into another folder (its name becomes the mod path)
"""
import argparse
import os
import re
import shutil
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
DEV = os.path.dirname(TOOLS)                  # <mod>/.dev
MOD = os.path.dirname(DEV)                    # data/mods/fort9000dev
DEFAULT_TARGET = os.path.join(os.path.dirname(MOD), "fort9000")
ID_FILE = "publishedfileid.lua"
FORBIDDEN_EXT = (".bat", ".cmd", ".exe")      # the game's upload validation refuses these anywhere in the folder
SKIP_NAMES = ("__pycache__",)
SKIP_EXT = (".pyc", ".tmp")


def skipped(name):
    return name.startswith(".") or name in SKIP_NAMES or name.endswith(SKIP_EXT) or ".bak" in name


def collect(src):
    """Relative paths of all files to publish."""
    out = []
    for entry in sorted(os.listdir(src)):
        if skipped(entry) or entry == ID_FILE:
            continue
        path = os.path.join(src, entry)
        if os.path.isfile(path):
            out.append(entry)
            continue
        for root, dirs, files in os.walk(path):
            dirs[:] = sorted(d for d in dirs if not skipped(d))
            for f in sorted(files):
                if not skipped(f):
                    out.append(os.path.relpath(os.path.join(root, f), src))
    return out


def check(src, files):
    errors = []
    for root, dirs, fs in os.walk(src):
        dirs[:] = [d for d in dirs if d != ".git"]
        for f in fs:
            if f.lower().endswith(FORBIDDEN_EXT):
                errors.append("forbidden file type (upload refuses it, even in dot folders): "
                              + os.path.relpath(os.path.join(root, f), src))
    with open(os.path.join(src, "ai", "fortplans.lua"), encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    if re.search(r"^\s*Probe\s*=", text, re.M):
        errors.append("ai/fortplans.lua: Probe is switched on")
    m = re.search(r"^\s*Force\s*=\s*\{(.*?)\}", text, re.M | re.S)
    if m and re.search(r"\w+\s*=", m.group(1)):
        errors.append("ai/fortplans.lua: Force is not empty: " + " ".join(m.group(1).split()))
    if not files:
        errors.append("nothing to publish")
    return errors


def transform(rel, data, mod_name):
    """Contents of a file in the published mod."""
    if os.path.basename(rel) == "displayname.lua":
        text = data.decode("utf-16")
        text = text.replace(' DEV"', '"')
        return text.encode("utf-16")           # UTF-16 LE with BOM, as the game writes it
    if rel.endswith(".lua"):
        return data.replace(b"mods/fort9000dev/", ("mods/%s/" % mod_name).encode("ascii"))
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", default=DEFAULT_TARGET)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    target = os.path.abspath(args.target)
    mod_name = os.path.basename(target)

    if os.path.normcase(target) == os.path.normcase(MOD):
        sys.exit("ERROR target is the dev folder itself")
    if not re.match(r"^[A-Za-z0-9]+$", mod_name):
        sys.exit("ERROR target folder name must be alphanumeric ASCII (Workshop rule): " + mod_name)
    git_dir = os.path.join(target, ".git")
    if os.path.isdir(git_dir) and os.listdir(git_dir):
        sys.exit("ERROR target contains a git repo, refusing to empty it: " + target)

    files = collect(MOD)
    errors = check(MOD, files)
    for e in errors:
        print("ERROR " + e)
    if errors:
        sys.exit(1)

    print("Publish %s -> %s (%d files)" % (MOD, target, len(files)))
    if args.dry_run:
        for f in files:
            print("  " + f.replace(os.sep, "/"))
        return

    os.makedirs(target, exist_ok=True)
    for entry in os.listdir(target):
        if entry == ID_FILE:
            continue
        path = os.path.join(target, entry)
        try:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
        except OSError as e:
            print("WARNING could not remove %s: %s" % (entry, e))

    left = []
    for rel in files:
        with open(os.path.join(MOD, rel), "rb") as fh:
            data = transform(rel, fh.read(), mod_name)
        dst = os.path.join(target, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as fh:
            fh.write(data)
        if rel.endswith(".lua") and b"fort9000dev" in data:
            left.append(rel)
    for rel in left:
        print("WARNING still mentions fort9000dev: " + rel.replace(os.sep, "/"))

    # the Workshop item id: keep it in git (.dev/) and in the target, so later uploads update the same item
    kept = os.path.join(DEV, ID_FILE)
    live = os.path.join(target, ID_FILE)
    if os.path.isfile(live):
        shutil.copyfile(live, kept)
        print("Workshop id: %s (copied to .dev/%s, commit it)" % (open(live).read().strip(), ID_FILE))
    elif os.path.isfile(kept):
        shutil.copyfile(kept, live)
        print("Workshop id restored from .dev/" + ID_FILE)
    else:
        print("No Workshop id yet (the game writes %s after the first upload)" % ID_FILE)
    print("Done. Upload mods/%s in the game; enable only one of FORT 9000 AI / FORT 9000 AI DEV at a time." % mod_name)


if __name__ == "__main__":
    main()
