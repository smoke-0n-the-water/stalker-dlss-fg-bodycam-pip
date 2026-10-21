# Distribution

The engine release and compatibility patches are separate packages. Install matching versions.
See the [README installation steps](../README.md#installation) for the player-facing procedure.

| Package | Contents | Destination |
| --- | --- | --- |
| Core | Engine binaries and matching `00_modded_exes_gamedata.db0` | `Anomaly/bin` and `Anomaly/db/mods` |
| GAMMA Patch | Compatibility shaders/scripts, core mirrors and reticle assets | A separate MO2 mod; required for GAMMA and 3DSS setups |
| Grass Optimisation | Optional instanced-grass and grass-shadow shaders | A separate MO2 mod |

The core ZIP also carries the README, license, third-party notices, distribution guide and a
build manifest with artifact hashes. Check the manifest before mixing downloaded packages.

## File ownership

Core gamedata is intended for plain Anomaly. Files that override 3DSS, SSS, Beef's NVG or other
GAMMA mods belong in the GAMMA Patch. Optic mappings specific to GAMMA weapons also live there.

Some core scripts and text files are deliberately mirrored in the GAMMA Patch because loose
files in an existing GAMMA installation override the core database. Those mirrors must match
the engine version, allowing only line-ending differences. Intentional shader overrides include
`night_vision.h` in the GAMMA Patch and the two `deffer_tree_branch_*.vs` files in the Grass Patch.

Scope passes that require 3DSS or SSS are gated by their framework/rendering prerequisites.
The optional grass path falls back to the engine's standard path without the Grass Patch.

## Packaging

Engine packaging, deployment and validation utilities are maintained locally and are not part of
this source snapshot. Both patch repositories retain their own `tools/package.py` and release
workflows. Their archives contain `gamedata/`, `meta.ini`, `README.md` and `PROVENANCE.md` at the root
for MO2 installation.

Keep the original component licenses and provenance when redistributing; see
[PROVENANCE.md](PROVENANCE.md).
