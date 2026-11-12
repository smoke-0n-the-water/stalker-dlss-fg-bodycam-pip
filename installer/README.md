# Slop-Ray Engine installer and uninstaller

Plain-text PowerShell (Windows PowerShell 5.1, built into Windows) behind
double-click `.bat` files. No admin rights, no downloads, nothing written
outside the player's GAMMA folder.

## For players

**Install:** double-click `INSTALL - double-click me.bat` in the pack folder.
It finds GAMMA, checks everything, shows what it will do, and asks once.
Nothing is changed before you answer Y.

**Uninstall:** double-click `UNINSTALL - Slop-Ray Engine.bat`. The installer
puts a copy in your GAMMA folder, so you don't need the pack any more. It
shows what it will put back and asks once.

**Free the disk space afterwards (optional):** after an uninstall that said
`UNINSTALLED - your GAMMA install is back as it was`, double-click
`CLEAN UP BACKUPS - Slop-Ray Engine.bat`. It only deletes backup copies of
files that are already back in place, and asks first.

Close the game and MO2 before any of them.

**Something stopped half-way** (power cut, closed window)? Run the same
`.bat` again. An unfinished install is undone first. An unfinished uninstall
carries on.

Your settings files: the installer sets MSAA off, VSync off, the upscaler and
frame gen once, on the first install. If you change them later, a re-run or
the uninstaller leaves your choice alone.

## How your files are kept safe

Everything lives in one folder inside your GAMMA folder: `.slopray`.

| Folder / file | What it is |
|---|---|
| `record.json` | What every touched file looked like before Slop-Ray, its SHA-256, and what Slop-Ray put there. |
| `backup\` | Your original files, at the same paths as in the game folder. |
| `recovery\<run>\` | Files you changed after install, moved here instead of being deleted or overwritten. |
| `runs\<run>\journal.jsonl` | Every step a run took, written before the step, so a stopped run can be undone. |
| `logs\` | A full log of every install and uninstall, plus each uninstall's report. |
| `tool\` | The uninstaller itself. |

**Installing a file** (`Install-OwnedFile` in `SlopRay.psm1`):

1. The path is checked: it must stay inside the GAMMA folder, with no `..`,
   and no link or junction anywhere below the GAMMA folder.
2. If a file of yours is there, it is **moved** into `backup\` (never copied
   over, never deleted). The first backup of a path is kept forever, so an
   update never mistakes an older Slop-Ray file for your original.
3. The new file is copied next to its target, checked by SHA-256, then
   renamed into place.
4. A file that changed since Slop-Ray wrote it goes to `recovery\`.

**Uninstalling a file** compares three hashes: your original, what Slop-Ray
installed, and what is on disk now.

| Case | What it means | What happens |
|---|---|---|
| A | We replaced your file and nobody changed it since | your original is copied back from `backup\` (checked by hash) |
| B | We replaced your file and you changed it since | left as is, reported; your original stays in `backup\` |
| C | We added the file, unchanged | removed |
| D | We added the file, you changed it | moved to `recovery\` |
| E | Your original backup is missing or damaged | left as is, reported |
| U | An older pack replaced it and never saved your original | left as is, reported (GAMMA's launcher update restores GAMMA's own files) |

**When in doubt, your file is kept.** A file is only removed when its hash
proves it is exactly what Slop-Ray wrote.

**MO2 and user.ltx** are changed per line, not per file. Each line Slop-Ray
set is recorded with its value before and after. The uninstaller puts a line
back only if it still holds Slop-Ray's value, so your later mod-order changes,
new mods and settings are kept. Only the profile that was active at install is
touched. The launch entry is removed only if its title and exe path are still
the ones the installer wrote.

**Mod folders** are never deleted as a whole. Slop-Ray's files are removed one
by one, then a folder is removed only if it is empty.

**3DSS:** the installer never changes the `410- 3DSS for GAMMA` files. If
`GAMMA\3DSS_backup` exists (left by v0.5.0-dev's 5.02 merge), the uninstaller
puts it back as 410, but only if the current 410 is that merge
(`z_3dss_lens_hider.script`) and the backup is 4.17 (`lewd_lens_hider.script`).
The merged folder is moved to `recovery\`, not deleted.

**Older packs (before this installer):** they left `.old` files and no record.
The first run of this installer takes them over. A file is recognised as an
older Slop-Ray file only by its SHA-256 being in `catalogue.json`, never by its
name. Its `.old` becomes the original in `backup\`. Old Slop-Ray mod folders
are removed file by file. Any file in them that can't be proven ours goes to
`recovery\`. Outside our own mod folders, a catalogued file is kept in
`backup\`, never deleted, because GAMMA may ship the very same file (VC
runtimes, `nvngx_dlss.dll`).

**One install record per GAMMA folder.** The record stores the folder path and
the drive's serial number. A `.slopray` folder copied along with the game to
another place is refused.

## Switches

`install.ps1`: `-DryRun` (show the plan, change nothing), `-Dlss5`,
`-GamePath "<folder>"`, `-Yes` (don't ask), `-GpuName` (testing).
`uninstall.ps1`: `-DryRun`, `-GamePath`, `-Yes`. `cleanup_backups.ps1`:
`-GamePath`, `-Yes`.

## Building a pack

Copy into the pack root, next to the `STEP` folders: `install.ps1`,
`uninstall.ps1`, `cleanup_backups.ps1`, `SlopRay.psm1`, `catalogue.json` and
the four `.bat` files. After a release, rebuild the catalogue so the next
version recognises its files:

```bash
python -I installer/tools/build_catalogue.py "C:\Users\Walter\Tools" installer/catalogue.json
```

It reads every `*Full Pack*.zip` and `*UPDATE*.zip` under `share_pack_*`.
A release that isn't on disk any more isn't in the catalogue, and its files
are then treated as the player's (kept, never deleted).

## Tests

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File installer/tests/run.ps1
```

They build fake GAMMA folders under `%TEMP%` whose names contain spaces,
brackets, `&`, `!`, `%` and a non-ASCII letter. Every run gets `-GamePath` to
its own fake folder, so a real install is never touched. `-Only S7` runs one
scenario. `-Keep` keeps the folders. Set `SR_TEST_VERBOSE=1` to see the
installer output.

| Scenario | Checks |
|---|---|
| S0 | dry run changes nothing, makes no `.slopray` |
| S1 | fresh install: originals in backup, no `.old`, mods ticked and ordered, other profile untouched, no unrelated file changed |
| S2 | install over an existing setup with ReShade's `dxgi.dll`: left alone, then a clean uninstall |
| S3 | upgrade from an older pack: `.old` adopted as the original, old mod removed, uninstall restores the true original modlist, ini and user.ltx |
| S4 | installer run twice: second run changes nothing, keeps the player's setting, no extra backups |
| S5 | install killed half-way: next run undoes it exactly, then installs |
| S6 | install failing at 3 points (engine files, after the modlist edit, after every settings edit): undone exactly |
| S7 | normal uninstall: everything back; S15 second uninstall does nothing; cleanup; reinstall after cleanup |
| S8 | player changed files after install: cases B and D, own setting kept, cleanup refuses |
| S9 / S10 | backup missing / damaged: case E, nothing overwritten, damaged backup not deleted |
| S11 | player re-ordered MO2 and added a mod: their order and lines kept, ours removed |
| S12 | custom files in 410 untouched; v0.5.0-dev `3DSS_backup` swapped back |
| S14 | uninstall killed half-way: next run finishes it |
| S16 | a mod zip that climbs out of its folder, and a junction in `Anomaly\bin`: both refused and undone |

Test hooks (only used by the tests): `SLOPRAY_TEST_NO_PROCESS_CHECK`,
`SLOPRAY_TEST_FAIL_AFTER=N`, `SLOPRAY_TEST_KILL_AFTER=N`.

## Known limits

- The two `.bat` files in the GAMMA folder stay after an uninstall. A batch
  file can't delete itself while it runs. Keeping it also lets you run it
  again.
- MO2 edits `meta.ini` inside mod folders on its own. If it did, re-running the
  installer or uninstalling moves MO2's version to `recovery\`.
- The Glossy Puddles add-on that v0.5.2-dev built for you has no hash in the
  catalogue (it is different for everyone), so the first run of this installer
  treats it as yours and keeps a copy in `backup\`.
- Tested on fake GAMMA folders and with the real v0.5.2-dev pack contents on a
  fake GAMMA folder. Not yet run on a real GAMMA install or with real MO2.
