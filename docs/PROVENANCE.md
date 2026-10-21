# Source provenance

This v0.3 source snapshot combines the Bodycam fork with upstream engine and PiP work.
Squashing the development history does not change ownership of the included code or assets.

| Component | Source / checkpoint |
| --- | --- |
| Published Bodycam baseline | `asuparabekon/xray-monolith-bodycam`, `bodycam-mt` commit `2c4420b60e6abec4685d352615068248200ea485` |
| Development snapshot | Full-history Bodycam checkpoint `42e4bb7b8ed1e1cb9327ce5a6511b6de8f4463bc`, before public documentation and file-selection cleanup |
| Monolith MT integration | `themrdemonized/xray-monolith`, merged through `871e24912` |
| PiP integration | `xray-monolith-pip`, integrated through `406e7c015`; original PiP work credited to TheLostInPlace (m22) |
| Reference motion and optics | Accepted reference checkpoint `2b72576a7c8b4c0d6c2fb28f4f7483373ccb66ad`; original recording/export inputs are maintained separately |
| Optick submodule | `bombomby/optick`, pinned by the Git submodule entry and `.gitmodules` |

## Included assets and notices

Reference character packets are included under `gamedata/bodycam_reference/character/`.
Optics constants are under `gamedata/bodycam_reference/optics/`; the adjacent
`source_glass_cb.provenance.json` records the glass constants' source hashes and output hash.
Generated source headers retain their source/generator notices. Historical paths in provenance
records identify the original inputs; they are not installation requirements.

The root [License.txt](../License.txt), [THIRD-PARTY-NOTICES.txt](../THIRD-PARTY-NOTICES.txt),
component licenses and source-level notices remain part of the distribution. This summary does
not replace those notices or grant additional rights to third-party material.

## Separate projects

- [GAMMA compatibility patch](https://github.com/asuparabekon/xray-monolith-bodycam-gamma-compatibility-patch):
  mod-specific shaders, scripts and reticle assets; its `PROVENANCE.md` records their sources.
- [Grass Optimisation patch](https://github.com/asuparabekon/xray-monolith-bodycam-grass-optimisation-patch):
  optional grass shaders and their upstream attribution.
- [3DSS Reticle Studio](https://github.com/asuparabekon/3dss-reticle-studio): separate reticle-authoring application.

Development handoffs, investigations, fixtures and tools are kept outside this public snapshot.
