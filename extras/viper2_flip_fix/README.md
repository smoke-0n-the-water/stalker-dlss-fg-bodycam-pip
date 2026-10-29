# Viper 2 Magnifier Flip Crash Fix

For `xx-AR15 ''Viper2'' SuperCustom - Pedritos`. **Must sit below that mod in
MO2.**

## Why

Flipping a magnifier or an offset sight switches the weapon to its `_off`
section. The Viper 2 pack declares six `_off` HUD sections and ships none of
their models, so the engine fails the load and it is a hard FATAL:

```
FATAL ERROR  CModelPool::Instance_Load  ModelPool.cpp:123
Can't find model file
'anomaly_weapons\wpn_ar15_viper2_custom\wpn_ar15_viper2_custom_e0t2_magd_off_hud.ogf'
```

A missing `item_visual` .ogf is always a hard FATAL on first display, never a
silent fallback.

All six are the same defect, so every flip on that weapon crashes, not only the
reported one:

```
aim_t2_magd_off        Aimpoint T2 + magnifier
atacr_voodoo_off       ATACR + Voodoo offset mount
e0t2_magd_off          EOTech EXPS + FTC magnifier     <- reported
e0t2_magd_unity_off    EOTech EXPS + magnifier, Unity mount
narcos_kit_off         Narcos kit
uh1_voodoo_off         UH-1 + Voodoo offset mount
```

Each one's non-off model does ship, so all six `item_visual` entries are
repointed at it.

## Consequence

The flip plays its animation and changes behaviour as normal, but the model
does not visibly change: the magnifier stays drawn in line rather than folding
aside. That is cosmetic. The real fix is the weapon pack shipping its six
missing models.

## DLTX note

Weapon sections are patched through the **system** namespace, so this is
`gamedata/configs/mod_system_zzz_viper2_offfix.ltx`. A DLTX file named after the
weapon's own ltx, `mod_w_ar15_viper2_custom_hud_*.ltx`, is never read and fails
silently with no log line. 3DSS does it correctly in
`mod_system_zz_3dss_ak104_alfa.ltx` using `![wpn_ak104_alfa_hud]`.
