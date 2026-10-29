# Bodycam Scope Effects Guard

Holds `bodycam_scope_effects_enable` off while you are aimed, and restores it
the moment you lower the weapon.

## Why

The bodycam reference image is only presented on the deferred-glass path
(`phase_3DSSReticle`, `referenceImage`). Optics that never get deferred glass
reach that branch with nothing resolved behind them, and the replacement blanks
the lens instead of decorating it. Night vision and thermal optics are excluded
from deferred glass by design:

```cpp
return !(scope_glass_deferred_current() && ps_r2_nightvision > 0);
```

Measured with the `[SVP-BRANCH]` diagnostic over one session, four optics:

| optic (eyep_r) | branch | result |
| --- | --- | --- |
| blank 0.0100 | deferred | fine |
| vortex, Razor HD 0.0157 | deferred | fine |
| 1pn93 0.0123 | stock, `deferred=0 refImage=1` | blank lens |
| echo1 0.0182 | stock, `deferred=0` | blank lens |

The hybrid reflex-plus-magnifier optics blank the same way, confirmed on the
EOTech EXPS with FTC magnifier. Those bind geometric specs, so optic class does
not predict the breakage on its own.

**This is a workaround.** The engine bug is real and is not fixed here. Two
attempts at an engine fix, gating `referenceImage` on
`scope_glass_deferred_current()` and dropping the composite's depth write, both
left the lens blank and were reverted.

## Modes

`gamedata/configs/bodycam_scope_effects_guard.ltx`, `[settings] mode`:

- `pip` (default): hold whenever PiP scopes are on, `r__svpscope` non-zero, for
  every optic. The cvar is re-read as you aim, so `r__svpscope 0` gives the
  bodycam glass back live with no restart.
- `list`: hold only for the optics in `[broken_optics]`.

The list is 20 entries, every runtime section bound to a spec whose
`optic_class` is `display` or `night_vision_display`, plus the EOTech and UH-1
magnifier hybrids. Matching was verified over all 7030 weapon and `up_sect`
sections in a full GAMMA install: 431/431 of the listed-optic variants match,
zero false positives.

A value you set to off yourself is left alone.

## Install

Ordinary MO2 mod. Anywhere below the Bodycam GAMMA Patch; it is a script and a
config and conflicts with nothing.
