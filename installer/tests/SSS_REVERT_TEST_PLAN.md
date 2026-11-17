# SSS revert: test plan

Written 2026-11-14, before any code. The SSS revert turns an **SSS24 setup** back
into the SSS 23.5 setup Slop-Ray supports (terms: `installer\CONTEXT.md`). Uninstall
must bring the SSS24 setup back. Decisions behind this: grilling Q1 to Q19.

## Success criteria

1. Every new scenario below passes in `tests\run.ps1`.
2. Every existing scenario (S0 to S18) still passes, unchanged. A plain GAMMA
   install must see no difference at all.
3. A `-DryRun` on Walter's real install (no SSS24) reports no SSS revert.
4. The friend's real run matches the manual checklist at the end.

## Detection rules under test

These are the rules the scenarios pin down. Each is an assumption taken from the
real files on 2026-11-14; see "Assumptions" for what is unverified.

| Rule | Signature |
|---|---|
| **SSS24 mod** | One ticked mod that ships BOTH `gamedata\shaders\r3\screenspace_materials.h` and `gamedata\scripts\demonized_sss_imgui.script`. Folder name is ignored. |
| **Other SSS24-shader mod** (stop) | A ticked mod that ships `screenspace_materials.h` but is not the SSS24 mod (e.g. an Atmospherics SSS24 variant). |
| **SSS 23.5** | The mod `190- Screen Space Shaders 23 - Ascii1457` exists and its `gamedata\shaders\r3\screenspace_reflections.h` has the 23.5 signature (`float HudMask, inout float2 noise`). |
| **Foreign db0 mod** | A ticked mod that ships `db\mods\00_modded_exes_gamedata.db0` whose hash is not in the Release catalogue. Applies with or without SSS24 (Q14). |
| **GAMMA patch source** | `GAMMA\.Grok's Modpack Installer\G.A.M.M.A\modpack_patches\gamedata`. Only `gamedata` is restored, never its `bin` or `db`. |
| **Loose Streamline DLLs** | `Anomaly\bin\sl.*.dll` (not `bin\streamline\`). |

Unticked mods never count for any rule.

## Fixture: `New-Sss24Setup` (on top of `New-Gamma`)

Mimics a player who followed the SSS24 tutorial, steps 4 to 9:

- `GAMMA\mods\190- Screen Space Shaders 23 - Ascii1457`: `screenspace_reflections.h` with the 23.5 signature. Line `-` (unticked, tutorial step 4).
- `GAMMA\mods\SSS24 my install`: deliberately odd folder name. It ships `screenspace_materials.h`, `demonized_sss_imgui.script`, and `db\mods\ssfx_rain_footsteps.db0` (real SSS24 module 05 ships this db0, so the db0 rule must ignore it). Line `+`.
- `GAMMA\mods\STALKER-Anomaly-modded-exes-MT-TEST_2026.10.11`: ships `db\mods\00_modded_exes_gamedata.db0` ('demonized db0'). Line `+`.
- `Anomaly\bin\AnomalyDX11AVX.exe` = 'SSS24 exe'. `sl.common.dll`, `sl.dlss.dll`, `sl.interposer.dll`, `sl.pcl.dll`, `sl.reflex.dll` = 'sss24 sl 2.11.1 <name>'. `nvngx_dlss.dll` = 'sss24 dlss 310.6'.
- `Anomaly\gamedata`: only `configs\` remains (tutorial step 9). It contains `configs\x.ltx` = 'player config'.
- `GAMMA\.Grok's Modpack Installer\G.A.M.M.A\modpack_patches\gamedata`: `configs\x.ltx` = 'gamma config', `shaders\r3\combine_2_naa.ps`, `scripts\gamma_patch.script`. Also `modpack_patches\bin\AnomalyDX11.exe`, to prove `bin` is not copied.
- Second profile `Other` with `+SSS24 my install`, to prove only the active profile is edited.

## Scenarios

### S19 SSS24 setup: install

Install exits 0. Then check:

- **Modlist (active profile):**
  - `-SSS24 my install`
  - `-STALKER-Anomaly-modded-exes-MT-TEST_2026.10.11`
  - `+190- Screen Space Shaders 23 - Ascii1457`
  - `+My Own Mod`, `-Disabled Mod` untouched; order of the player's lines unchanged.
- **Other profile** is byte-identical.
- **Loose DLLs:** the five `Anomaly\bin\sl.*.dll` are gone from `bin` and sit in `.slopray\backup\Anomaly\bin\` with the same content. `bin\streamline\sl.common.dll` from STEP 7 is installed.
- **GAMMA patch files:**
  - `Anomaly\gamedata\shaders\r3\combine_2_naa.ps` and `scripts\gamma_patch.script` exist with the modpack content.
  - `configs\x.ltx` still says 'player config'.
  - `Anomaly\bin\AnomalyDX11.exe` was not created from `modpack_patches\bin`.
- **Record:**
  - the two restored files are Introduced files;
  - the five DLL moves are recorded;
  - the three modlist lines are Owned keys with the SSS24 values as baseline.
- **Output** has the SSS revert summary block: the SSS24 mod name, the MT-TEST mod name, the restored file count, the DLL count, and "uninstall brings SSS24 back".
- **Nothing else changed:** same "no unrelated file changed" check as S1, widened only by the paths above.

### S19b SSS24 setup: install, then uninstall

`Assert-BackToOriginal` against the snapshot taken before the install:

- the SSS24, MT-TEST and SSS 23 lines are back as they were;
- the five DLLs are back in `bin`;
- the restored patch files are gone;
- the SSS24 exe is back.

### S20 SSS24 setup: dry run

`-DryRun` exits 0 and changes nothing (no `.slopray`). Output names the planned revert: both mods to untick, SSS 23 to tick, 2 patch files, 5 DLLs.

### S21 stops: SSS 23 missing

Fixture without the `190- Screen Space Shaders 23 - Ascii1457` folder. Install exits 1 and nothing changes (snapshot identical, no `.slopray`). Output says SSS 23.5 is needed and names the folder.

### S21b stops: SSS 23 is not 23.5

The SSS 23 folder has the pre-23.5 signature (`float gloss, inout float3 color`). Same expectations as S21. The message says the version is wrong.

### S22 stops: another ticked mod carries SSS24 shaders

Add a ticked `Atmos SSS24 variant` mod with `screenspace_materials.h` but no `demonized_sss_imgui.script`. Install exits 1 and nothing changes. Output lists `Atmos SSS24 variant`.

### S22b unticked SSS24-shader mod is ignored

The same mod, but its line is `-`. Install exits 0 and the revert runs as in S19. The mod's line stays `-`.

### S23 stops: GAMMA patch source missing

SSS24 setup without the `modpack_patches` folder. Install exits 1 and nothing changes. Output names the missing folder.

### S24 plain GAMMA: no revert

The standard `New-Gamma` (no SSS24). Its `Anomaly\gamedata` lacks patch files, and a `modpack_patches` folder exists:

- install exits 0;
- the output has no SSS revert block;
- no patch file is copied;
- the modlist result equals S1's.

### S25 foreign db0 mod without SSS24

On plain GAMMA, add:

- ticked `Old modded exes`, shipping a non-catalogued `00_modded_exes_gamedata.db0`;
- ticked `Repack of ours`, shipping a db0 whose hash IS in the catalogue.

After install:

- `-Old modded exes`;
- `+Repack of ours` stays ticked;
- uninstall ticks `Old modded exes` again.

### S26 SSS24 setup: install twice, then uninstall

The second install exits 0 and reports nothing left to revert. The record baseline still holds the SSS24 values (not the reverted ones). Uninstall then passes `Assert-BackToOriginal`.

### S27 player re-ticks SSS24 after install

After install, the player edits the modlist back to `+SSS24 my install`. Then:

- **Uninstall:** the SSS24 line stays `+` (Drift rule: an Owned key is reverted only while it still equals what Slop-Ray wrote). The other reverted items are restored.
- **Separately, re-running install instead:** the SSS24 setup is detected again and unticked.

### S28 SSS24 setup: install killed halfway

Run with `SLOPRAY_TEST_KILL_AFTER` at a step inside the revert (after the DLL moves, before the modlist write). The next install run Undoes it. The snapshot is identical to the pre-install one: DLLs back in `bin`, no restored patch files, modlist unchanged.

### S29 SSS 23.5 required on every install (added 2026-11-14)

Without SSS24 too: a ticked mod must have the SSS 23.5 declaration
(`float4 gloss, inout float4 color, float HudMask, inout float2 noise`). Atmospherics and Glossy
Puddles add `float hemi`, so they match neither 23.5 nor the pre-23.5 form.

- **S29:** SSS 23 is unticked. Refused: exit 1, nothing changed.
- **S29b:** an older SSS (`float gloss, inout float3 color`) is ticked ABOVE 23.5. Refused, and the message names it.
- **S29c:** an older SSS is ticked BELOW 23.5, and an Atmos-style mod is above it. Installs fine, and the output says "SSS 23.5: ok".

### Test harness fix (2026-11-14)

The suite's `Diff` function never ran: in Windows PowerShell, `diff` is a
built-in alias for `Compare-Object`, and aliases win over functions. Every
"nothing changed" and "back to original" check passed without comparing anything.

It is renamed to `Compare-Snap`. After the rename, every old scenario still
passes.

## Manual checks

**Walter's machine** (no SSS24; never launch MO2 from a script):

1. `tests\run.ps1`: all scenarios pass, and the count equals the old count plus the new checks.
2. `install.ps1 -DryRun` against the real GAMMA root: no SSS revert block, no stop. This guards against false positives on a real mod list.

**Friend's machine** (first real SSS24 run, private zip):

1. The friend backs up their whole GAMMA root first.
2. Run `-DryRun` and send a screenshot. Check that it names their actual SSS24 mod and MT-TEST mod.
3. Install, then send the SUMMARY screenshot.
4. In MO2:
   - the SSS24 mod and the MT-TEST mod are unticked;
   - SSS 23 is ticked;
   - the pack mods are at the bottom.
5. Launch through `Anomaly (DX12 + Frame Gen)` or DX11-AVX. Shaders compile (long first load), there is no FATAL, and a save loads.
6. Optional: run uninstall, check that MO2 shows the SSS24 ticks again and that `Anomaly\bin` has SSS24's exe and `sl.*.dll`.

## Assumptions to confirm before coding

1. **MT-TEST mod layout:** demonized's `STALKER-Anomaly-modded-exes-MT-TEST_2026.10.11.zip` (with `bin` deleted) is assumed to ship `db\mods\00_modded_exes_gamedata.db0` at the mod root. Not verified: the zip was not downloaded. If it ships the db0 elsewhere, the db0 rule and the S19 fixture change.
2. **SSS24's non-AVX exe:** the tutorial also puts SSS24's `AnomalyDX11.exe` in `bin`. Our pack does not replace it. A player launching the non-AVX DX11 entry would run SSS24's exe with our db0. This plan leaves it alone; say if the revert should handle it.
3. **Restore only on an SSS24 setup:** patch files are restored only when an SSS24 setup is detected. A plain GAMMA install missing some of them (on purpose or not) is not touched (S24).
4. **SSS24 RC6+:** the signatures are from RC5. A later RC that renames `screenspace_materials.h` or the ImGui script would slip past detection, and the install would run on SSS24 shaders.
