"""Build catalogue.json: the SHA-256 of every file a past Slop-Ray release installed.

The installer uses it to prove a file is ours when no install record exists
(players upgrading from a pack older than the record). Ownership is never
guessed from a file name; a hash that is not in here is treated as the player's.

Usage:  python -I build_catalogue.py <folder with share_pack_* dirs> <out catalogue.json>

Reads every "*Full Pack*.zip" and "*UPDATE*.zip" under share_pack_* folders.
Only files under a "STEP ..." folder are counted (that is what got installed),
plus every file inside the STEP 2 / STEP 3 mod zips.
"""
import hashlib
import io
import json
import os
import sys
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def in_step(path):
    return any(part.lower().startswith("step ") for part in path.split("/")[:-1])


def walk(zf, label, hashes, mods):
    for info in zf.infolist():
        name = info.filename.replace("\\", "/")
        if name.endswith("/"):
            continue
        data = zf.read(info)
        if name.lower().endswith(".zip") and in_step(name):
            # a pack MO2 mod (STEP 2 / STEP 3): its folder name = zip name
            mods.add(os.path.splitext(os.path.basename(name))[0])
            walk(zipfile.ZipFile(io.BytesIO(data)), label + "!" + name, hashes, mods)
            continue
        if "!" in label or in_step(name):
            hashes.setdefault(sha(data), label.split("!")[-1] + ":" + name)


def main():
    top, out = sys.argv[1], sys.argv[2]
    hashes, mods, releases = {}, set(), []
    seen = set()
    for d in sorted(os.listdir(top)):
        if not d.lower().startswith("share_pack"):
            continue
        for base, _, files in os.walk(os.path.join(top, d)):
            for f in sorted(files):
                if not f.lower().endswith(".zip") or not ("full pack" in f.lower() or "update" in f.lower()):
                    continue
                p = os.path.join(base, f)
                key = (f, os.path.getsize(p))
                if key in seen:
                    continue
                seen.add(key)
                print("reading", p, flush=True)
                with zipfile.ZipFile(p) as zf:
                    walk(zf, f, hashes, mods)
                releases.append(f)
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"releases": releases, "modNames": sorted(mods), "hashes": hashes}, fh, indent=0, sort_keys=True)
    print(len(releases), "zips,", len(mods), "mod names,", len(hashes), "hashes ->", out)


if __name__ == "__main__":
    main()
