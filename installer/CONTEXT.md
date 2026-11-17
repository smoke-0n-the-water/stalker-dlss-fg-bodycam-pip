# Slop-Ray Installer

How the Slop-Ray Engine pack is put onto, and taken back off, a player's GAMMA install without losing anything that belongs to the player.

## Language

### Install state

**GAMMA root**:
The folder that holds both `Anomaly` and `GAMMA` (MO2) for one installation.
_Avoid_: game folder, install dir

**Baseline**:
What every path Slop-Ray touches looked like before the first Slop-Ray install on that GAMMA root. Captured once per path, the first time that path is touched, and never replaced afterwards by an upgrade, reinstall or repair.
_Avoid_: original, backup, vanilla

**Install record**:
The per-GAMMA-root record of the Baseline, every path Slop-Ray placed and its installed hash, and the operations performed. It is bound to exactly one GAMMA root.
_Avoid_: manifest file, log

**Journal**:
The append-only list of operations an install or uninstall has started and finished, used to recover after an interruption.

**Adoption**:
Building an Install record for a GAMMA root that already has an older Slop-Ray install but no record, using existing `.old` files and the Release catalogue.

**Unknown Baseline**:
A Replaced file whose pre-Slop-Ray content was never captured (no `.old`, or the `.old` is itself a Slop-Ray release file). Uninstall leaves the current file and points the player to GAMMA's own updater.

**Undo**:
Reverting an unfinished install or uninstall, step by step, from its Journal. A run is undone, never resumed.
_Avoid_: rollback, resume

**Release catalogue**:
The list of hashes of every file each past Slop-Ray release installed. Used to prove a file is ours. Never guessed from a filename.

### Ownership of a path

**Replaced file**:
A path that existed in the Baseline and that Slop-Ray overwrote.

**Introduced file**:
A path that did not exist in the Baseline and that Slop-Ray created.

**Pack mod**:
An MO2 mod folder Slop-Ray creates (STEP 2 mods, STEP 3 add-ons, generated add-ons), identified by its marker file and the Release catalogue, not by its folder name.

**Generated add-on**:
A Pack mod the installer builds from the player's own files (for example the Glossy Puddles add-on), so its content differs per player.

**Drift**:
A path whose current hash matches neither its Baseline nor its installed hash: the player or another tool changed it after Slop-Ray did. A drifted path is never overwritten or deleted automatically.
_Avoid_: user modification, conflict

**Recovery folder**:
Where a drifted file is moved instead of being deleted or overwritten, kept until the player removes it.

### Settings edits

**Owned key**:
A single key or line in `user.ltx`, `ModOrganizer.ini` or `modlist.txt` that Slop-Ray set, recorded with its Baseline value and the value Slop-Ray wrote. It is reverted only while its current value still equals what Slop-Ray wrote.
