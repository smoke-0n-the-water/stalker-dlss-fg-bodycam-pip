# S.T.A.L.K.E.R. Bodycam + PiP + DLSS + Frame Gen

My merge of bodycam, true PiP scopes, DLSS/FSR and DX12 frame gen into one engine for G.A.M.M.A.
I play on it daily (RTX 5080, 4K).

## Versions

- `v0.3`: bodycam 0.3 + PiP + DLSS/FSR + frame gen, plus my crash fixes
- `v0.3.1`: same thing on bodycam 0.3.1. Needs Bodycam GAMMA Patch 2.0.x and Grass Optimisation 5.0.0

## What I changed

- The DX12 build (`AnomalyDX12.exe`) has everything, frame gen included. The DX11-AVX build has everything except frame gen.
- Fixed a crash when loading a save on the DX12 build (stale `pBaseRT` pointer).
- Frame gen kept switching itself off every time you scoped in. Fixed.
- Running low on VRAM with frame gen on used to crash the game. Now it just logs a warning.
- Lens flares and UI no longer break during the scope pass.
- Added a separate `phasepp` timer to `r__svp_stats` (COMBINE2 was hiding it).

## Building

VS 2022 Build Tools, run `git submodule update --init`, then build `src\engine-vs2022.sln` as `DX12|x64`
or `DX11-AVX|x64`. Frame gen needs `bin\D3D12\D3D12Core.dll`, `bin\streamline\`, the
`amd_fidelityfx_*_dx12.dll` files and `nvngx_dlss.dll` next to the exe. They're not in this repo.

## Built from

- asuparabekon/xray-monolith-bodycam: bodycam, PiP scopes
- m1RAGE5/xray-monolith-pip-dlss: PiP + DLSS merge
- themrdemonized/xray-monolith: base engine

Below is the original bodycam README (it says DX11 only; this fork adds the DX12 build).
