# 3DSS ZoomCalc Syntax Fix

Overrides one file from `410- 3DSS for GAMMA`. **Must sit below it in MO2** or
it loses the conflict and does nothing.

## Why

3DSS ships `zzz_mspizza_Godis_ZoomCalc.script` with a C-style `/* ... */`
comment block. Lua has no such syntax, so the file fails to parse,
`on_game_start` never runs, `actor_on_weapon_zoom_in` is never registered, and

```lua
obj:cast_Weapon():SetZoomFactor(tonumber(new_fov))
```

never fires. Symptom: FOV drifts toward 120 while shooting at magnification,
because nothing is holding the scope's zoom.

## Two changes

1. `/*` to `--[[` and `*/` to `]]`, so the file parses. The block it wraps is
   dead demo code, so nothing of substance changes.

2. The alternate-sight branch, which was

   ```lua
   if last_alt ~= 0 then new_fov = 0 end   -- then SetZoomFactor(0)
   ```

   now returns instead. **Repairing the script without this second change is a
   regression.** Switching to a canted or offset sight pushed zoom factor 0
   onto the weapon and the main scope went black. `last_alt` is only cleared by
   `actor_on_weapon_zoom_type_changed`, which carries the original author's own
   comment, `does not work`, so it can stay stuck non-zero and every later aim
   keeps forcing zero.

## Deliberately not fixed

The sister script `zzz_mspizza_Godis_Zoom_control.script` has a separate syntax
error, a missing `)`. It is left broken on purpose: it is a near-duplicate that
defines the same globals and registers the same callbacks, so repairing both
makes them fight over `SetZoomFactor` on every zoom-in.

## Caveat

With the script alive, zoom factors change for every 3DSS scope, since it is
the thing that sets them and it had not been running. Magnification may feel
different. Untick the mod for stock behaviour.
