# Slop-Ray Engine: S.T.A.L.K.E.R. GAMMA Bodycam + PiP + DLSS + Frame Gen

## What's new in v0.7-dev
<img width="1000" height="538" alt="aznoiuvulebedp4lmwro" src="https://github.com/user-attachments/assets/5e03d0ce-1a84-4895-a653-f1df6af746fc" />




- **Fixed: offline A-Life was frozen.** Since v0.5.0-dev, squads away from you never moved, smart terrains never refilled, and **delivery quests** came with no target and could not be finished. Squads move again and new delivery quests work. A delivery quest you took on an older build stays broken: abandon it and take a new one. Huge thanks to **ProgWalrus** for finding this one.
- **No more AVX2.** Both exes now need only **AVX** (any CPU from about 2011 on). On a 9800X3D the AVX build benchmarks the same as the old AVX2 one.
- **Fixed: DX11 exe crash on AVX-only CPUs** (Intel 2nd/3rd gen, AMD FX).
- **Crash fixes from Quark Engine 1.5.1:**
  - heap corruption after changing the screen resolution
  - taking or destroying a dead NPC's weapon
  - a weapon or grenade launcher with an ammo type past its list
  - aiming at an item with no collision
  - a net packet overflow that corrupted memory, and a save that rolls back the one object record that would not fit instead of writing a broken save
  - a queued spawn whose object was already gone
  - a GOAP planner step with no evaluator
  - script `fs:r_close` that never closed the file
- **Fixed: crash on a headshot / hit while scoped** (a wallmark on a stale bone).
- **Fixed: textures stuck black** (and a black scope reflection) with Texture Residency on. PiP scope textures are never lowered.
- **Dual-CCD Ryzen with equal cache on both CCDs** (e.g. 9950X): every core is used again.
- **Smoother CPU side, also from Quark 1.5.1:** cheaper pickup highlight, NPC memory and hearing, `alife()` and `str_explode` calls from Lua, LTX/DLTX loading, LOD billboards, and client state export capped at 100 per second.
- **Better crash logs:** the error logger now names the object, the save and the level a crash happened in.
- **PiP scopes:**
  - **Scope Resolution** setting sizes the scope image from the lens on screen
  - frame gen shows the 3DSS reticle from the presented frame (no reticle ghosting)
  - fixed the zoomed corner image with a reticle while aiming below DLAA
  - the scope view keeps its own TAA under DLSS/FSR, unjittered and without sharpening
  - **F11 > PiP scope > Super Sampling 1.5** stops grass and foliage flicker in the scope
- **Installer:**
  - lists every G.A.M.M.A. install it finds and asks which one; new `INSTALL - choose folder.bat`
  - works when Anomaly and the GAMMA (MO2) folder are in different places
  - says clearly "install G.A.M.M.A. first" when it isn't there
  - no more false "installed file(s) did not verify" after a DLSS 5 install or on RTX 50
  - warns about mods and loose files that break the pack (old PiP mods, other NVG mods, loose shaders)
  - unticks G.A.M.M.A.'s `453- Items Model Drop` only when it clashes with Model Drop 15 (the uninstaller ticks it again)
  - set up SSS 24? It switches back to SSS 23.5 for you; the uninstaller brings SSS 24 back
  - prints the pack version and the installer's SHA-256 at the top: this release is `70937E079897`
- **DLSS 5: choose your OptiScaler F5 version.** `INSTALL + DLSS 5 (RTX, experimental).bat` keeps **0.1.35**, the version played since v0.5. The new **`INSTALL + DLSS 5 - OptiScaler 0.1.38 (newer, untested).bat`** installs **0.1.38**, which adds DLSS 5 "Model resolution". Run the other `.bat` to swap back. In both, OptiScaler's own frame generator stays off, so frame gen is still the game's own (Settings > Video > Basic). Don't pick "f5low" in the OptiScaler menu.

## Which file do I want?

| File | For |
|---|---|
| `GAMMA v0.7-dev + DLSS 0.721 + Frame Gen - Full Pack.zip` | **Everyone.** New install, or update from any older pack (v0.3 to v0.6). |
| `AnomalyDX12-v0.7-dev-pdb.zip` | Debug symbols for the DX12 exe. Only for crash reports. |
| `AnomalyDX11AVX-v0.7-dev-pdb.zip` | Debug symbols for the DX11 exe. Only for crash reports. |

## Install

1. **Model Drop 15** installed and ticked in MO2 (link in `READ ME FIRST.txt`).
2. Close the game and MO2.
3. Extract the Full Pack, double-click **`INSTALL - double-click me.bat`**. Check what it says it will do and any `[note]` lines, then type **Y**.
   - More than one G.A.M.M.A., or it picked the wrong one? Use **`INSTALL - choose folder.bat`** and paste your G.A.M.M.A. folder.
   - Updating from an older pack? Just run the installer again. It replaces the old mods and keeps your originals and your own settings.
   - Want DLSS 5 (RTX, experimental, costs fps)? Run **`INSTALL + DLSS 5 (RTX, experimental).bat`** (OptiScaler 0.1.35) or **`INSTALL + DLSS 5 - OptiScaler 0.1.38 (newer, untested).bat`** (adds "Model resolution") instead.
4. **NVIDIA App: Smooth Motion OFF** for Anomaly.
5. MO2 dropdown: **Anomaly (DX12 + Frame Gen)** > Run. The first launch rebuilds shaders and looks frozen for a few minutes.

Recommended for PiP scopes: F11 > PiP scope > Super Sampling **1.5**.

## Uninstall

Close the game and MO2, then double-click **`UNINSTALL - Slop-Ray Engine.bat`** in your G.A.M.M.A. folder. It puts your original files, MO2 mod list, launch entry and video settings back, and keeps anything you changed after installing. Launch the normal DX11 entry afterwards.

## Known limits

- Both exes need a CPU with **AVX** (Intel Core 2nd gen / AMD FX or newer). The installer checks and warns you.
- Delivery quests accepted before this update stay broken. Abandon and retake them.
- On v0.5.0-dev to v0.6-dev and can't update yet? The Lua stopgap "Offline A-Life Scheduler Fix v1.0" by tommusicmeister-rgb restores offline A-Life, and switches itself off on this build.
- Frame generation is DX12 only. DLSS frame gen needs an RTX 20-50 with HAGS on; FSR frame gen works on any DX12 GPU. Upscaler on and VSync off.
- Linux / Proton: the installer is Windows-only. Follow `READ ME - Linux manual install.txt`.
- A crash dump when quitting is harmless (it happens after the game has saved and unloaded).
- Dev build: tested on one machine so far. If anything breaks, post `Anomaly\appdata\logs\xray_<name>.log`, the newest file in `%APPDATA%\QUARK-ENGINE\ERROR` and the installer log from `.slopray\logs` in your G.A.M.M.A. folder.

## Credits

**Engine code this build is forked from and merged from:**

- **GSC Game World**: the X-Ray engine (S.T.A.L.K.E.R.)
- **Anomaly team**: S.T.A.L.K.E.R. Anomaly engine
- **themrdemonized**: [X-Ray Monolith](https://github.com/themrdemonized/xray-monolith), the engine G.A.M.M.A. ships, and its MT branch
- **asuparabekon**: [Immersive Bodycam engine](https://github.com/asuparabekon/xray-monolith-bodycam) 0.3.1, G.A.M.M.A. patch 2.0.1, grass 5.0.0
- **TheLostInPlace**: bodycam 0.3.1 grass renderer
- **m1RAGE5**: [PiP bodycam + DLSS merge](https://github.com/m1RAGE5/xray-monolith-pip-dlss), original DLSS-FSR3 compatibility patch
- **brodrigz**: [native DLSS/FSR upscaling, DX12 presentation bridge and frame generation](https://github.com/brodrigz/xray-monolith), compatibility patch 0.721 (Atmos fixes)
- **Quark Engine team**: [Quark Engine](https://github.com/quark-engine-stalker/quark-engine) 1.5.1 fixes and optimisations; every merged Quark commit credits its upstream commit
- **noisethanks**: [MM engine](https://github.com/noisethanks/xray-monolith) research (TBB job system, texture streaming)
- **Bodycam community**: Bodycam DLSS Scope Fix

**Bundled tools:**

- **janblade**: [OptiScaler F5](https://github.com/janblade/OptiScaler-F5-DLSSNR-Multipass) (DLSS 5 + built-in RTX 20/30/40 frame gen unlock), GPL-3.0
- **wilsjo2 / OptiScaler**: earlier DLSS 5 fork
- **ShortFuse (RenoDX)**: cross-GPU Neural Rendering runtime
- **NODIX-TECH**: [DLSS 5 Manager](https://github.com/NODIX-TECH/DLSS-5-MANAGER) 1.3.8 (source of the 310.9.16 DLSS 5 library)
- **NVIDIA, AMD, Microsoft**: Streamline / DLSS, FidelityFX, Agility SDK and the Visual C++ runtime, under their licences (`STEP 6\Licenses`, `STEP 7\Licenses-DX12`)

**Bug reports and fixes:**

- **ProgWalrus**: found the major offline A-Life bug (frozen squads, empty smart terrains, broken delivery quests)
- **Totalwipeout**: delivery quest report
- **Corrado**: found the RTX 20/30/40 frame gen unlock recipe




