"""Write pack-manifest.json into a pack folder: the SHA-256 of every file under its STEP folders.

The installer checks the pack against it before changing anything, so a cut-off
or damaged download stops with "re-download the full pack".
Run it LAST, after the pack folder is final (any change afterwards makes the check fail).

Usage:  python -I build_pack_manifest.py <pack folder> [pack name]
"""
import hashlib
import json
import os
import sys


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


pack = sys.argv[1]
files = {}
for top in sorted(d for d in os.listdir(pack) if d.upper().startswith("STEP ") and os.path.isdir(os.path.join(pack, d))):
    for dirpath, _, names in os.walk(os.path.join(pack, top)):
        for n in names:
            full = os.path.join(dirpath, n)
            files[os.path.relpath(full, pack).replace("\\", "/")] = sha(full)
out = {"pack": sys.argv[2] if len(sys.argv) > 2 else os.path.basename(os.path.abspath(pack)), "files": dict(sorted(files.items()))}
with open(os.path.join(pack, "pack-manifest.json"), "w", encoding="utf-8", newline="\n") as f:
    json.dump(out, f, indent=1)
print(len(files), "files listed")
