# ===========================================================================
#  1-click installer: GAMMA v0.7-dev (DX12 + frame gen + bodycam + PiP
#  scopes + DLSS/FSR)
#
#  PLAIN TEXT SCRIPT. Read it in Notepad first if you like. It:
#     1. finds your GAMMA folder and checks everything BEFORE changing anything
#     2. shows what it will do and asks once
#     3. copies the engine (DX11 + DX12) and verifies every copy by SHA-256.
#        Every file of yours it replaces is MOVED into <game folder>\.slopray\backup
#        first (never deleted, never overwritten). The first backup of a file
#        is kept forever, so updates never lose your real original.
#     4. unpacks the MO2 mods + the add-ons your mod list needs
#     5. ticks + orders them in your active MO2 profile and unticks
#        old/conflicting versions. Screen Space Shaders 24 found: switches
#        back to SSS 23.5 (the uninstaller brings SSS24 back)
#     6. adds "Anomaly (DX12 + Frame Gen)" to MO2's launch dropdown
#     7. RTX 20/30/40 only: installs OptiScaler (STEP 6) with its built-in
#        frame gen unlock, so DLSS 2x/3x/4x shows up in the game menu
#     8. every run: MSAA off (the upscaler needs it). first install only: VSync off, upscaler on (DLSS on
#        RTX, FSR otherwise), frame gen on for RTX 40/50
#     9. moves the shader cache aside (not deleted)
#    10. puts "UNINSTALL - Slop-Ray Engine.bat" in your GAMMA folder
#  Everything it does is written to <game folder>\.slopray\record.json, so the
#  uninstaller can put your files back. If it fails or is stopped part-way,
#  it undoes what it did (or offers to on the next run).
#  Never touches the internet, never writes outside your STALKER folder.
#  Safe to run again.
#     -DryRun     show what would happen, change nothing
#     -Dlss5      also install DLSS 5 / Neural Rendering (STEP 6, RTX only)
#     -OptiScaler 0.1.38   OptiScaler F5 version (STEP 6). Default 0.1.35, the one
#                 played since v0.5; 0.1.38 adds DLSS 5 "Model resolution", untested
#     -GamePath "D:\Games\S.T.A.L.K.E.R. GAMMA"   skip auto-detection (the folder
#                 with Anomaly + GAMMA in it, or either of those two)
#     -AskPath    don't search, ask for the folder (INSTALL - choose folder.bat)
#     -Yes        don't ask, just do it
#     -GpuName "NVIDIA GeForce RTX 3060"   testing only: pretend this GPU
# ===========================================================================
[CmdletBinding()]
param(
    [string]$GamePath,
    [switch]$AskPath,
    [switch]$DryRun,
    [switch]$Dlss5,
    [ValidateSet('0.1.35', '0.1.38')][string]$OptiScaler = '0.1.35',
    [switch]$Yes,
    [string]$GpuName
)

$ErrorActionPreference = 'Stop'
$pack = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$pack\SlopRay.psm1" -Force -DisableNameChecking
$PackVersion = 'v0.7-dev'
$OptiDefault = '0.1.35'      # the F5 version in STEP 6 itself; others are "STEP 6\F5 <version>"
$fail = 0
$todo = New-Object System.Collections.Generic.List[string]
$utf8 = New-Object System.Text.UTF8Encoding($false)   # MO2 files have no BOM
$logTmp = "$env:TEMP\slopray_install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
try { Start-Transcript -LiteralPath $logTmp | Out-Null } catch { }

function Say  ($m) { Write-Host $m }
function Good ($m) { Write-Host "  [ok]   $m"   -ForegroundColor Green }
function Warn ($m) { Write-Host "  [note] $m"   -ForegroundColor Yellow }
function Bad  ($m) { Write-Host "  [STOP] $m"   -ForegroundColor Red; $script:fail++ }
function Head ($m) {
    Write-Host ""
    Write-Host ("-" * 70)
    Write-Host "  $m"
    Write-Host ("-" * 70)
}
function Pause-End ($code) {
    try { Stop-Transcript | Out-Null } catch { }
    if ($script:sr -and (Test-Path -LiteralPath $script:sr.Dir)) {
        try {
            [void][IO.Directory]::CreateDirectory("$($script:sr.Dir)\logs")
            Copy-Item -LiteralPath $logTmp "$($script:sr.Dir)\logs\" -Force
            Say "  log: $($script:sr.Dir)\logs\$(Split-Path $logTmp -Leaf)"
        } catch { }
    }
    if (-not $DryRun -and -not $Yes) { try { Read-Host "Press Enter to close" | Out-Null } catch { } }
    exit $code
}
function Confirm-Go ($q) {
    if ($Yes) { return $true }
    try { return ((Read-Host "$q (Y/N)") -match '^\s*(y|yes)\s*$') } catch { return $false }
}

Say ""
Say "==================================================================="
Say "  GAMMA $PackVersion installer (DX12 + Frame Gen + DLSS/FSR)"
# which pack build this is (players run old zips); the release notes list the same hash
Say "  install.ps1 $((Get-Item -LiteralPath $MyInvocation.MyCommand.Path).LastWriteTime.ToString('yyyy-MM-dd'))  SHA-256 $((Get-Sha $MyInvocation.MyCommand.Path).Substring(0, 12))"
if ($DryRun) { Say "  *** DRY RUN - nothing will be changed ***" }
Say "==================================================================="

# --- 1. nothing may be running ------------------------------------------
Head "Checking the game and MO2 are closed"
$busy = Get-BusyGameProcesses
if ($busy) {
    $names = $busy -join ', '
    if ($DryRun) { Warn "$names is open. Fine for -DryRun, close it before a real run." }
    else {
        Bad "Close these first, then run me again: $names"
        Say "(MO2 rewrites its mod list when it closes, so it must not be open.)"
        Pause-End 1
    }
} else { Good "closed" }

# --- 1b. CPU: both exes (DX12 and DX11-AVX) are built for AVX ---------------
Head "Checking CPU (the engine needs AVX)"
$avx = $null
try {
    Add-Type -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(uint f);' -Name K -Namespace GammaCpu -ErrorAction Stop
    $avx = [GammaCpu.K]::IsProcessorFeaturePresent(39)   # PF_AVX_INSTRUCTIONS_AVAILABLE
} catch { }
if ($avx -eq $true) { Good "AVX supported" }
elseif ($avx -eq $false) {
    Warn "your CPU has NO AVX: neither Slop-Ray exe (DX12 + Frame Gen, DX11-AVX) will run on it."
    Warn "only G.A.M.M.A.'s own non-AVX DX11 entry works on this CPU. See README: HARD REQUIREMENT."
    $todo.Add("Your CPU has no AVX: Slop-Ray will not run on it. Use G.A.M.M.A.'s own non-AVX DX11 entry in MO2")
} else { Warn "could not check AVX - see README: HARD REQUIREMENT" }

# --- 2. find the game ----------------------------------------------------
Head "Finding your STALKER GAMMA folder"
try { $inst = Select-GammaInstall $GamePath $pack -Ask:$AskPath -NoPrompt:$Yes } catch { Bad $_.Exception.Message; Pause-End 1 }
$root    = $inst.Home          # where .slopray and the uninstaller go
$anomaly = $inst.Anomaly
$gamma   = $inst.Mo2           # the G.A.M.M.A. MO2 folder
$modsDir = "$gamma\mods"
if ($inst.Split) {
    Good "found Anomaly:           $anomaly"
    Good "found G.A.M.M.A. (MO2):  $gamma"
} else { Good "found: $root" }

try { $sr = Open-SlopRay $inst "$pack\catalogue.json" } catch { Bad $_.Exception.Message; Pause-End 1 }
if ($sr.WasNew) { Good "no earlier Slop-Ray record (first install with this installer)" }
else { Good "Slop-Ray record found (last state: $($sr.Record.state))" }

# a run that was stopped part-way: undo it before anything else
if (-not $sr.WasNew -and $sr.Record.state -eq 'installing') {
    Head "The last install did not finish"
    Say "  It was stopped part-way. I can undo what it changed, so your files are"
    Say "  exactly as they were before it started. Then run me again."
    if ($DryRun) { Say "  (dry run: would offer to undo it)"; Pause-End 0 }
    if (-not (Confirm-Go "Undo the unfinished install now?")) { Say "  Nothing changed."; Pause-End 1 }
    $problems = Undo-Run $sr $sr.Record.runId
    if ($problems.Count) { foreach ($p in $problems) { Warn $p }; Bad "undo left $($problems.Count) thing(s) to check (above)" }
    else { Good "undone - your files are as they were. Run the installer again." }
    Pause-End $(if ($problems.Count) { 1 } else { 0 })
}
if (-not $sr.WasNew -and $sr.Record.state -eq 'uninstalling') {
    Bad "an uninstall did not finish. Run 'UNINSTALL - Slop-Ray Engine.bat' again first."
    Pause-End 1
}

# --- 2b. pack check ---------------------------------------------------------
# pack-manifest.json (written when the pack is built) lists every pack file and its SHA-256.
# A cut-off or damaged download is caught here, before anything else is read from the pack
# (a cut-off zip would otherwise stop the installer with a confusing error) and before
# anything is changed. (catalogue.json cannot do this: it only holds the hashes of PAST releases.)
Head "Checking the pack files"
$manifestFile = "$pack\pack-manifest.json"
if (-not (Test-Path -LiteralPath $manifestFile)) {
    Warn "this pack has no pack-manifest.json, so its files were not checked against a list."
} else {
    $manifest = (Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json).files.PSObject.Properties
    $packBad = @()
    foreach ($e in ($manifest | Sort-Object Name)) {
        $f = "$pack\$($e.Name.Replace('/', [string][char]92))"
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { $packBad += "$($e.Name) (missing)" }
        elseif ((Get-Sha $f) -ne $e.Value) { $packBad += "$($e.Name) (damaged)" }
    }
    if ($packBad.Count) {
        Bad "this pack is incomplete or damaged: $($packBad.Count) of $(@($manifest).Count) files are missing or different. Re-download the full pack and run me again. Nothing was changed."
        foreach ($n in ($packBad | Select-Object -First 5)) { Say "     $n" }
        if ($packBad.Count -gt 5) { Say "     ... and $($packBad.Count - 5) more" }
        Pause-End 1
    }
    Good "Pack check: every file is there and matches its checksum ($(@($manifest).Count) files)"
}

# --- 3. what gets copied -------------------------------------------------
# Nothing is written in this part: it only builds the list of changes.
# A path that is not safe (a link or junction inside the game folder) stops
# the installer here, before anything is changed.
function Get-PlanPath ($rel) {
    try { Resolve-Rel $sr $rel } catch { Bad "$($_.Exception.Message). Nothing was changed."; Pause-End 1 }
}
$place = New-Object System.Collections.Generic.List[object]   # @{ Rel; Src; Set }
function Add-Set ($label, $sourceDir, $destRel, $skip = @()) {
    if (-not (Test-Path -LiteralPath $sourceDir)) { Bad "$label is missing from this pack"; return }
    foreach ($f in Get-ChildItem -LiteralPath $sourceDir -Recurse -File) {
        $rel = $f.FullName.Substring($sourceDir.Length).TrimStart('\')
        if ($skip | Where-Object { $rel -like $_ }) { continue }
        $place.Add(@{ Rel = "$destRel\$rel"; Src = $f.FullName; Set = $label })
    }
}
function Step-Dir ($prefix) {
    Get-ChildItem -LiteralPath $pack -Directory | Where-Object { $_.Name -like "$prefix*" } | Select-Object -First 1
}

Head "Engine (DX11 + DX12 frame gen)"
$s1 = Step-Dir 'STEP 1'
$s7 = Step-Dir 'STEP 7'
if ($s1) {
    Add-Set "DX11 engine" "$($s1.FullName)\bin" "Anomaly\bin"
    Add-Set "gamedata archive" "$($s1.FullName)\db" "Anomaly\db"
} else { Bad "STEP 1 folder missing from this pack" }
if ($s7) { Add-Set "DX12 engine + frame gen" "$($s7.FullName)\bin" "Anomaly\bin" }
else     { Bad "STEP 7 folder missing from this pack" }
# an engine change needs a fresh shader cache
$engineChange = $false
foreach ($p in $place) {
    $d = Get-PlanPath $p.Rel
    if ($p.Rel -match '\.(exe|db0)$' -and (-not (Test-Path -LiteralPath $d) -or (Get-Sha $d) -ne (Get-Sha $p.Src))) { $engineChange = $true }
}
Good "$($place.Count) engine files to copy$(if ($engineChange) { '' } else { ' (engine already this version)' })"

# GPU decides the OptiScaler step and the default video settings below.
$gpu = $GpuName
if (-not $gpu) {
    try { $gpu = (Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -Expand Name) -join ' / ' } catch { $gpu = '' }
}
$rtx       = $gpu -match 'NVIDIA.*RTX'
$rtxFg     = $gpu -match 'RTX\s*(40|50)\d\d'          # DLSS frame gen without any unlock
$needsUnlk = $gpu -match 'RTX\s*(20|30|40)\d\d'       # unlock: 20/30 get FG, 40 gets 3x/4x

# HAGS (Hardware-accelerated GPU scheduling) should be on for the DX12 exe. Read only: the
# installer never changes Windows settings, it tells you where the switch is.
if ($place | Where-Object { $_.Rel -like '*\AnomalyDX12.exe' }) {
    $hags = Get-HwSchMode
    if ($hags -eq 2) { Good "GPU scheduling (HAGS): on" }
    else {
        $hagsMsg = "Hardware-accelerated GPU scheduling (HAGS) is $(if ($null -eq $hags) { 'off or not available' } else { 'off' }). The DX12 exe is meant to run with it on. Turn it on in Windows: Settings > System > Display > Graphics > Default graphics settings > Hardware-accelerated GPU scheduling, then restart Windows."
        Warn $hagsMsg
        $todo.Add($hagsMsg)
    }
}

# OptiScaler (STEP 6, janblade's F5 build). Its built-in unlock ([MFGUnlock]
# RTX40/RTX2030 = detect) only switches on for the GPU family that needs it.
# Installed automatically on RTX 20/30/40, or anywhere with -Dlss5.
$doOpti = $needsUnlk -or $Dlss5
$optiIni = $null
Head "OptiScaler (frame gen unlock$(if ($Dlss5) { ' + DLSS 5' }))"
Say "  GPU: $(if ($gpu) { $gpu } else { 'unknown' })"
if (-not $doOpti) {
    Say "  not needed on this GPU (RTX 50 has 3x/4x built in; other GPUs use FSR)."
    $optiNote = "OptiScaler: not installed, not needed on this GPU ($gpu)"
} else {
    $s6 = Step-Dir 'STEP 6'
    $existing = "$anomaly\bin\dxgi.dll"
    $ok = [bool]$s6
    if (-not $s6) { Bad "STEP 6 folder missing from this pack" }
    if ($ok -and (Test-Path -LiteralPath $existing) -and
        (Get-Item -LiteralPath $existing).VersionInfo.OriginalFilename -ne 'OptiScaler.dll' -and
        -not (Test-Ours $sr 'Anomaly\bin\dxgi.dll' (Get-Sha $existing))) {
        Warn "Anomaly\bin\dxgi.dll exists and is NOT OptiScaler (ReShade?). Not overwriting it."
        $optiNote = "OptiScaler: NOT installed, Anomaly\bin\dxgi.dll is another program (ReShade?). Remove it and run again for the frame gen unlock"
        Warn "No frame gen unlock: on RTX 20/30 the game menu will show no DLSS frame gen."
        $ok = $false
    }
    # STEP 6 holds the default F5 version; another version is a folder "F5 <version>" inside
    # it with only the files that differ (dxgi.dll, its ini, ...). -OptiScaler picks it.
    $s6v = $null
    if ($ok -and $OptiScaler -ne $OptiDefault) {
        $s6v = Get-ChildItem -LiteralPath $s6.FullName -Directory | Where-Object { $_.Name -eq "F5 $OptiScaler" } | Select-Object -First 1
        if (-not $s6v) { Bad "OptiScaler $OptiScaler is not in this pack (STEP 6\F5 $OptiScaler missing)"; $ok = $false }
    }
    if ($ok) {
        # licences stay in the pack, not in the game folder; the version folders are overlays
        $skip = @('README.md', 'TROUBLESHOOTING.md', 'LICENSE', 'Licenses\*', 'F5 *\*')
        if (-not $Dlss5) { $skip += 'nvngx_dlssnr.dll' }   # 276 MB NR model, DLSS 5 only
        if ($Dlss5) { $skip += 'OptiScaler.ini'; $optiIni = "$($s6.FullName)\OptiScaler.ini" }   # edited copy added below
        Add-Set "OptiScaler" $s6.FullName "Anomaly\bin" $skip
        if ($s6v) {
            foreach ($p in $place) {
                if ($p.Set -ne 'OptiScaler') { continue }
                $o = "$($s6v.FullName)\$($p.Rel.Substring('Anomaly\bin\'.Length))"
                if (Test-Path -LiteralPath $o -PathType Leaf) { $p.Src = $o }
            }
            if ($optiIni -and (Test-Path -LiteralPath "$($s6v.FullName)\OptiScaler.ini")) { $optiIni = "$($s6v.FullName)\OptiScaler.ini" }
        }
        Good "OptiScaler F5 $OptiScaler$(if ($OptiScaler -eq $OptiDefault) { ' (default)' })"
        if ($needsUnlk) { Good "frame gen unlock will be ready: pick DLSS 2x/3x/4x in Settings > Video > Basic" }
        $optiNote = "OptiScaler F5 $($OptiScaler): installed in Anomaly\bin (INS opens its menu in game)" + $(if ($Dlss5) { ", DLSS 5 on" } else { "" })
    }
}

# --- 5. MO2 profile ------------------------------------------------------
# (Decode-QtValue for the Qt-encoded selected_profile lives in SlopRay.psm1)

$ini = "$gamma\ModOrganizer.ini"
$modlist = $null
if (Test-Path -LiteralPath $ini) {
    $line = [IO.File]::ReadAllLines($ini, $utf8) | Where-Object { $_ -match '^selected_profile=' } | Select-Object -First 1
    if ($line) {
        $prof = Decode-QtValue ($line.Substring('selected_profile='.Length))
        $p = "$gamma\profiles\$prof\modlist.txt"
        if (Test-Path -LiteralPath $p) { $modlist = $p }
    }
}
if (-not $modlist) {
    $all = @(Get-ChildItem -LiteralPath "$gamma\profiles" -Directory -ErrorAction SilentlyContinue |
             Where-Object { Test-Path -LiteralPath "$($_.FullName)\modlist.txt" })
    if ($all.Count -eq 1) { $modlist = "$($all[0].FullName)\modlist.txt" }
}
$lines = @()
if ($modlist) {
    $lines = @([IO.File]::ReadAllLines($modlist, $utf8))
    Good "MO2 profile: $(Split-Path (Split-Path $modlist -Parent) -Leaf)"
} else {
    Warn "could not tell which MO2 profile is active - you will tick the mods by hand"
}
# the pack's own mods ("Add-on - Atmospherics RC7 users", "3 - ...") must never count
# as the player's mod: the RC7 pattern matched our own add-on and kept it on forever
function Is-PackMod ($name) {
    $name -like 'Add-on - *' -or $name -match '^\d - ' -or $sr.ModNames.ContainsKey($name) -or
    (Test-Path -LiteralPath "$modsDir\$name\slopray-mod.json")
}
function Is-Enabled ($pattern) {
    if ($modlist) { return [bool]($lines | Where-Object { $_.StartsWith('+') -and $_.Substring(1) -like $pattern -and -not (Is-PackMod $_.Substring(1)) }) }
    return [bool](Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern -and -not (Is-PackMod $_.Name) })
}
# a ticked mod (any name) that ships this file; folder names are whatever the player typed
function Is-EnabledByFile ($rel) {
    $names = if ($modlist) { $lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } }
             else { Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object Name }
    foreach ($n in $names) { if (Is-PackMod $n) { continue }; if (Test-Path -LiteralPath "$modsDir\$n\$rel") { return $true } }
    return $false
}
# same, but the file must also contain $text
function Is-EnabledByFileText ($rel, $text) {
    $names = if ($modlist) { $lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } }
             else { Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object Name }
    foreach ($n in $names) {
        if (Is-PackMod $n) { continue }
        $p = "$modsDir\$n\$rel"
        if ((Test-Path -LiteralPath $p) -and (Select-String -LiteralPath $p -Pattern $text -SimpleMatch -Quiet)) { return $true }
    }
    return $false
}

# --- Glossy Puddles add-on: built from the player's own Glossy shader -----
# brodrigz's Glossy compat file is Glossy's own deffer_impl_flat.ps plus two DLSS
# lines (checked 2026-11-12: Glossy 2.5 + these lines == his 0.721 file exactly).
# Glossy changes that shader between versions (2.1 .. 2.5) and between its
# "PBR" (Atmos RC7/RC8) and "SSS" (stock Atmos) builds, and a mismatched copy
# fails to compile. Adding the lines to the player's own file fits every one.
function Add-GlossyDlss ($text) {
    if ($text -match 'ssfx_mv_calc') { return $text }      # already has them
    $eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $ls = New-Object System.Collections.Generic.List[string]
    $ls.AddRange([string[]]($text -split [regex]::Escape($eol)))
    $inc = @(for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match '^\s*#include\s+"') { $i } })
    if ($inc.Count -eq 0) { return $null }
    $common = @($inc | Where-Object { $ls[$_] -match '^\s*#include\s+"common\.h"' })
    $start = -1
    for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match '^\s*O\s*=\s*pack_gbuffer\s*\(') { $start = $i; break } }
    if ($start -lt 0) { return $null }
    $end = -1
    for ($i = $start; $i -lt $ls.Count; $i++) {
        if (($ls[$i] -split '//', 2)[0].TrimEnd().EndsWith(');')) { $end = $i; break }
    }
    if ($end -lt 0) { return $null }
    # after the statement (past one blank line, as brodrigz places it), then the
    # include right after common.h; the include point is earlier, so insert it last
    $atVel = if ($end + 1 -lt $ls.Count -and -not $ls[$end + 1].Trim()) { $end + 2 } else { $end + 1 }
    $ls.InsertRange($atVel, [string[]]@(
        '  // Preserve Glossy Puddles shading while supplying temporal motion.',
        '  O.velocity = ssfx_mv_calc(I.vel_curr, I.vel_prev, 0, 0);'))
    $atInc = $(if ($common.Count) { $common[-1] } else { $inc[-1] }) + 1
    $ls.Insert($atInc, '#include "screenspace_mvectors.h"')
    return ($ls -join $eol)
}
# highest-priority ticked mod that is Glossy Puddles (monkey_gloss.script) and ships the shader
function Find-GlossyShader {
    $names = if ($modlist) { $lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } }
             else { Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object Name }
    foreach ($n in $names) {
        if (Is-PackMod $n) { continue }
        $sh = "$modsDir\$n\gamedata\shaders\r3\deffer_impl_flat.ps"
        if ((Test-Path -LiteralPath "$modsDir\$n\gamedata\scripts\monkey_gloss.script") -and (Test-Path -LiteralPath $sh)) {
            return @{ Mod = $n; Path = $sh
                      V25 = Test-Path -LiteralPath "$modsDir\$n\gamedata\shaders\r3\erandis_puddle_ripples.h" }
        }
    }
    return $null
}
$glossyText = $null; $glossyMeta = $null
function Install-GlossyAddon ($name) {
    $src = Find-GlossyShader
    if (-not $src) {
        Warn "Glossy Puddles is in your list but its shaders\r3\deffer_impl_flat.ps was not found - add-on skipped"
        $todo.Add("Glossy Puddles: install the matching zip from STEP 3\Glossy Puddles - manual install only, by hand")
        return
    }
    $patched = Add-GlossyDlss ([IO.File]::ReadAllText($src.Path))
    if (-not $patched) {
        Warn "Glossy Puddles: unknown shader layout in '$($src.Mod)' - add-on skipped"
        $todo.Add("Glossy Puddles: install the matching zip from STEP 3\Glossy Puddles - manual install only, by hand")
        return
    }
    # built again on every run, so a Glossy update on your side is picked up
    $script:glossyText = $patched
    $script:glossyMeta = "[General]`r`ngameName=stalkeranomaly`r`nmodid=0`r`nversion=1.0.0`r`ncomments=built by the installer from '$($src.Mod)' + DLSS motion vectors`r`n"
    $script:modPlan.Add(@{ Name = $name; Zip = $null })
    Good "$name (built from your '$($src.Mod)'$(if ($src.V25) { ', Glossy 2.5' }))"
    $script:installed.Add($name)
}

# --- 6. unpack mods ------------------------------------------------------
# modlist edits collected below: tick = force "+", drop = remove line (true) or untick (false)
$tickNames = @{}; $dropNames = @{}
# Texture Residency is off by default from v0.7.1. Once per install (the record remembers it) the
# master switch goes to 0 and pack mod 7 (menu + class rules) is left unticked; after that a
# re-run keeps whatever the player chose.
$texPattern = '7 - Tex Residency Classes*'
$texResMigrate = -not ($sr.Record -and $sr.Record.texResOff)
Head "MO2 mods to unpack"
$installed = New-Object System.Collections.Generic.List[string]
$modPlan = New-Object System.Collections.Generic.List[object]
$packNames = @{}     # every mod this pack ships, used or not
function Install-Mod ($zip) {
    $name = [IO.Path]::GetFileNameWithoutExtension($zip)
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try { $hasGd = [bool]($z.Entries | Where-Object { $_.FullName -match '^gamedata[\\/]' } | Select-Object -First 1) } finally { $z.Dispose() }
    if (-not $hasGd) { Bad "$name has no gamedata folder in the pack"; return }
    $script:modPlan.Add(@{ Name = $name; Zip = $zip })
    Good $name
    $script:installed.Add($name)
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not (Test-Path -LiteralPath $modsDir)) { Bad "no GAMMA\mods folder at $modsDir" }
else {
    $s2 = Step-Dir 'STEP 2'
    if (-not $s2) { Bad "STEP 2 folder missing from this pack" }
    else { foreach ($z in Get-ChildItem -LiteralPath $s2.FullName -Filter '*.zip' | Sort-Object Name) { $packNames[$z.BaseName] = $true; Install-Mod $z.FullName } }

    # add-ons only for mods you actually have ticked. Order here = lowest
    # priority first; Glossy Puddles must beat the Atmospherics one.
    Head "Add-ons for mods in your list"
    # Atmospherics 2.69 RC7.x or RC8 ticked? (by name, or by a file RC7.7+ and RC8 ship;
    # RC7.6 lacks that file but has RC7 in its name). RC8 takes the same add-ons as RC7:
    # its deffer_impl_flat.ps is identical (brodrigz 0.721), and it ships its own ssfx_*.
    $rc7 = (Is-Enabled "*Atmospherics*RC7*") -or (Is-Enabled "*Atmospherics*RC8*") -or
           (Is-EnabledByFile 'gamedata\shaders\r3\pbr_brdf_character.h')
    # RC7 and RC8 together fight over the same shaders. Only a warning: both stay ticked, which
    # one to keep is the player's call (the same add-on serves either).
    $rc7Names = @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } |
                  Where-Object { $_ -like '*Atmospherics*RC7*' -and -not (Is-PackMod $_) })
    $rc8Names = @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } |
                  Where-Object { $_ -like '*Atmospherics*RC8*' -and -not (Is-PackMod $_) })
    if ($rc7Names.Count -and $rc8Names.Count) {
        $bothMsg = "Atmospherics is ticked in both RC7 and RC8 versions: '$($rc7Names -join "', '")' and '$($rc8Names -join "', '")'. They overwrite each other's shaders. Nothing was unticked; in MO2 keep only the one you want."
        Warn $bothMsg
        $todo.Add($bothMsg)
    }
    # an Atmospherics mod that is neither RC7 nor RC8 (by name or file) gets the stock add-on
    if (-not $rc7) {
        $oddAtmos = @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } |
                      Where-Object { $_ -like '*Atmospherics*' -and -not (Is-PackMod $_) })
        if ($oddAtmos.Count) {
            $oddMsg = "'$($oddAtmos -join "', '")' is not recognised as RC7 or RC8, so the stock Atmospherics add-on will be used. If you use RC7 or RC8, check that this is the right version. Nothing was unticked."
            Warn $oddMsg
            $todo.Add($oddMsg)
        }
    }
    $addons = [ordered]@{
        # SSS 23 ssfx_il/ssfx_sss_ext + grass fallback + DLSS history fix. ONLY without RC7:
        # RC7 ships its own for every IL/SSR option ("IL Atmospherics", "SSR - Atmospherics"),
        # and an SSS copy on top of them = shader compile error (X3017)
        "Add-on - stock Atmospherics (no RC7)"   = $null
        "Add-on - Atmospherics RC7 users"        = "*Atmospherics*RC7*"
        "Add-on - Anti-Lag for GAMMA users"      = "Anti_Lag_for_GAMMA*"
        "Add-on - Better Beef's NVGs users"      = "*Better Beef's NVGs*"
        "Add-on - Glossy Puddles Overhaul users" = "*Glossy Puddles Overhaul*"
        "Add-on - Viper 2 flip crash fix"        = "*Viper2*SuperCustom*"
    }
    foreach ($k in $addons.Keys) { $packNames[$k] = $true }
    $s3 = Step-Dir 'STEP 3'
    $glossyKey = "Add-on - Glossy Puddles Overhaul users"
    foreach ($k in $addons.Keys) {
        $zip = if ($s3) { "$($s3.FullName)\$k.zip" } else { $null }
        # the Glossy add-on is built from the player's own Glossy files, not shipped
        if ($k -ne $glossyKey -and (-not $zip -or -not (Test-Path -LiteralPath $zip))) { Warn "$k missing from pack"; continue }
        $use = if ($addons[$k]) { Is-Enabled $addons[$k] } else { $false }
        if ($k -eq "Add-on - stock Atmospherics (no RC7)") { $use = -not $rc7 }
        # by content too: players name mod folders anything ("BetterBeefsNVGs_indiesunpraiser.19")
        if (-not $use -and $k -eq "Add-on - Atmospherics RC7 users") { $use = $rc7 }
        # Better Beef's (not plain Beef's): its nightvision_gen_1.ps needs NVGParams from its
        # night_vision.h; without this add-on mod 3/4 win that header = shader FATAL
        if (-not $use -and $k -eq "Add-on - Better Beef's NVGs users") { $use = Is-EnabledByFileText 'gamedata\shaders\r3\nightvision_gen_1.ps' 'NVGParams' }
        if (-not $use -and $k -eq "Add-on - Glossy Puddles Overhaul users") { $use = Is-EnabledByFile 'gamedata\scripts\monkey_gloss.script' }
        if ($use) { if ($k -eq $glossyKey) { Install-GlossyAddon $k } else { Install-Mod $zip } }
        else {
            Say "  skipped $k $(if ($k -like '*stock Atmospherics*') { '(Atmospherics RC7 in use)' } else { "(you don't use that mod)" })"
            # from an earlier run, for a mod no longer used (e.g. back to stock Atmos): untick
            if (Test-Path -LiteralPath "$modsDir\$k") { $dropNames[$k] = $false }
        }
    }
}

# --- 6a. leftover mods from older Slop-Ray packs --------------------------
# Only folders whose name is an old pack mod AND that hold at least one file
# proven ours by hash. Unproven files in them go to the recovery folder.
$leftovers = @()
if (Test-Path -LiteralPath $modsDir) {
    foreach ($d in Get-ChildItem -LiteralPath $modsDir -Directory) {
        if (-not $sr.ModNames.ContainsKey($d.Name) -or $packNames.ContainsKey($d.Name)) { continue }
        $proof = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force | Where-Object {
            $h = Get-Sha $_.FullName; $sr.Cat.Contains($h) -or ($sr.Record -and $sr.Record.files["GAMMA\mods\$($d.Name)\$($_.FullName.Substring($d.FullName.Length + 1))"])
        } | Select-Object -First 1
        if ($proof) { $leftovers += $d.Name; $dropNames[$d.Name] = $true }
    }
}
if ($leftovers.Count) { Head "Old Slop-Ray mods to remove"; foreach ($l in $leftovers) { Say "  $l" } }

# --- 6b. 3DSS: only one 3DSS mod ticked ---------------------------------
# Use the 3DSS GAMMA installs ("410- 3DSS for GAMMA": 4.17 on old GAMMA, 5.01 on
# updated GAMMA). Do NOT add a separate 3DSS (e.g. 5.02) next to it: both ship the
# same scope sections (mod_system_3dss_dummy_scopes.ltx) and DLTX stops the game
# with a duplicate-section FATAL (Corrado, 2026-11-05). Fresh GAMMA + 5.02 is also
# reported incompatible, so the pack no longer asks for 5.02.
Head "3DSS (only one 3DSS mod ticked)"
$tdss = Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '410- 3DSS for GAMMA*' } | Select-Object -First 1
if (-not $tdss) { Warn "no '410- 3DSS for GAMMA' mod found (GAMMA installs it; scopes need it)" }
elseif ($modlist) {
    $extra = @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } |
               Where-Object { $_ -ne $tdss.Name -and -not (Is-PackMod $_) -and
                              (Test-Path -LiteralPath "$modsDir\$_\gamedata\configs\mod_system_3dss_dummy_scopes.ltx") })
    foreach ($e in $extra) {
        Warn "second 3DSS mod ticked: '$e' (duplicate sections = FATAL at start). Unticking it, keeping '$($tdss.Name)'."
        $dropNames[$e] = $false
    }
    $tickNames[$tdss.Name] = $true
    if ($extra.Count -eq 0) { Good "only '$($tdss.Name)'" }
}
# v0.5.0-dev moved GAMMA's own 410 folder to GAMMA\3DSS_backup when it merged
# 3DSS 5.02. Remember it, so the uninstaller can offer to swap it back.
$legacy3dss = (Test-Path -LiteralPath "$gamma\3DSS_backup" -PathType Container) -and
              -not ($sr.Record -and $sr.Record.legacy3dss)
if ($legacy3dss) { Warn "found GAMMA\3DSS_backup (from v0.5.0-dev): the uninstaller can put it back" }

# --- 6c. SSS24 setup -> SSS 23.5 (SSS revert) ------------------------------
# The engine runs SSS 23.5, not Screen Space Shaders 24 (its shaders need SSS24's
# own exe). A player who followed the SSS24 install is switched back: SSS24 and
# demonized's modded-exes gamedata mod unticked, SSS 23 ticked, GAMMA's patch files
# that the SSS24 guide deleted from Anomaly\gamedata put back, SSS24's loose
# Streamline DLLs moved into the backup. The uninstaller undoes all of it.
# SSS24 is found by content (folder names are whatever the player typed):
# screenspace_materials.h is SSS24-only, its ImGui menu script marks the SSS24 mod itself.
$sss23Name   = '190- Screen Space Shaders 23 - Ascii1457'
# how SSS declares SSFX_ScreenSpaceReflections: 23.5 itself, and before 23.5. Atmospherics
# and Glossy Puddles add "float hemi" (built for 23.5) and match neither.
$ssr235      = 'float4 gloss, inout float4 color, float HudMask, inout float2 noise'
$ssrOld      = 'float gloss, inout float3 color'
$patchSrc    = "$gamma\.Grok's Modpack Installer\G.A.M.M.A\modpack_patches\gamedata"
$sssRevert   = $null
if ($modlist) {
    $tickedMods = @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } | Where-Object { -not (Is-PackMod $_) })
    $sss24Mods  = @($tickedMods | Where-Object { Test-Path -LiteralPath "$modsDir\$_\gamedata\shaders\r3\screenspace_materials.h" })
    if ($sss24Mods.Count) {
        Head "Screen Space Shaders 24 (switching back to SSS 23.5)"
        $main   = @($sss24Mods | Where-Object { Test-Path -LiteralPath "$modsDir\$_\gamedata\scripts\demonized_sss_imgui.script" })
        $others = @($sss24Mods | Where-Object { $main -notcontains $_ })
        $ssr    = "$modsDir\$sss23Name\gamedata\shaders\r3\screenspace_reflections.h"
        if ($others.Count) {
            Bad "these mods use SSS24 shaders and break on SSS 23.5: $($others -join ', '). Untick them (or install their SSS 23.5 version), then run again."
        }
        if (-not (Test-Path -LiteralPath "$modsDir\$sss23Name" -PathType Container)) {
            Bad "SSS24 found, but GAMMA's '$sss23Name' mod is missing. It is needed: reinstall it with the GAMMA launcher, then run again."
        } elseif (-not ((Test-Path -LiteralPath $ssr) -and (Select-String -LiteralPath $ssr -Pattern $ssr235 -SimpleMatch -Quiet))) {
            Bad "'$sss23Name' is not 23.5 (the version this engine needs). Update it with the GAMMA launcher, then run again."
        }
        if (-not (Test-Path -LiteralPath $patchSrc -PathType Container)) {
            Bad "SSS24 found, but GAMMA's own patch files are missing ($patchSrc). Run the GAMMA launcher's update, then run again."
        }
        if ($main.Count -and $fail -eq 0) {
            # only files that are missing, or that are ours from an earlier run; never a file of yours
            $restore = @(Get-ChildItem -LiteralPath $patchSrc -Recurse -File | ForEach-Object {
                $rel = 'Anomaly\gamedata\' + $_.FullName.Substring($patchSrc.Length + 1)
                $e = $(if ($sr.Record) { $sr.Record.files[$rel] } else { $null })
                if (-not (Test-Path -LiteralPath (Get-PlanPath $rel)) -or ($e -and $e.baseline -eq 'absent')) { @{ Rel = $rel; Src = $_.FullName } }
            })
            $slDlls = @(Get-ChildItem -LiteralPath "$anomaly\bin" -Filter 'sl.*.dll' -File -ErrorAction SilentlyContinue | ForEach-Object { "Anomaly\bin\$($_.Name)" })
            foreach ($n in $main) { $dropNames[$n] = $false }
            $tickNames[$sss23Name] = $true
            $sssRevert = @{ Mods = $main; Restore = $restore; Dlls = $slDlls }
            Good "SSS24 found: $($main -join ', ')"
            Say  "  will untick it, tick '$sss23Name', restore $($restore.Count) GAMMA patch files, move $($slDlls.Count) loose Streamline DLLs to the backup"
        }
    }
}

# --- 6d. other modded-exes gamedata: only ours may be active ----------------
# A ticked mod with its own 00_modded_exes_gamedata.db0 (e.g. demonized's MT-TEST
# from the SSS24 guide) wins over ours in MO2 and does not match this exe.
$foreignDb0 = @()
if ($modlist) {
    foreach ($n in @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } | Where-Object { -not (Is-PackMod $_) })) {
        $db = "$modsDir\$n\db\mods\00_modded_exes_gamedata.db0"
        if ((Test-Path -LiteralPath $db) -and -not $sr.Cat.Contains((Get-Sha $db))) { $foreignDb0 += $n; $dropNames[$n] = $false }
    }
    if ($foreignDb0.Count) {
        Head "Other modded exes gamedata (must not override this engine's)"
        foreach ($n in $foreignDb0) { Warn "unticking '$n': its 00_modded_exes_gamedata.db0 is for a different exe" }
    }
}

# --- 6e. SSS 23.5 must be ticked, and no older SSS above it -----------------
# Without SSS 23.5 the shaders miss the motion vectors DLSS needs; an older SSS
# that wins over it fails to compile (ssfx_ssr.ps X3017). Found by content.
# An SSS24 setup was handled in 6c (SSS 23 gets ticked there).
if ($modlist -and -not $sss24Mods.Count) {
    Head "Screen Space Shaders 23.5"
    $order = @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) } | Where-Object { -not (Is-PackMod $_) })
    $first235 = -1; $oldAbove = @()
    for ($i = 0; $i -lt $order.Count; $i++) {       # first line = highest priority
        $h = "$modsDir\$($order[$i])\gamedata\shaders\r3\screenspace_reflections.h"
        if (-not (Test-Path -LiteralPath $h)) { continue }
        if (Select-String -LiteralPath $h -Pattern $ssr235 -SimpleMatch -Quiet) { $first235 = $i; break }
        if (Select-String -LiteralPath $h -Pattern $ssrOld -SimpleMatch -Quiet) { $oldAbove += $order[$i] }
    }
    if ($first235 -lt 0) {
        Bad "no SSS 23.5 ticked in MO2. This engine needs it: tick '$sss23Name' (or reinstall it with the GAMMA launcher), then run again."
    } elseif ($oldAbove.Count) {
        Bad "an older Screen Space Shaders wins over SSS 23.5 and fails to compile: $($oldAbove -join ', '). Untick it, then run again."
    } else { Good "SSS 23.5: ok ('$($order[$first235])')" }
}

# --- 6f. things that break the pack but are yours to decide (warnings only) --
# Seen in player reports: old bodycam/PiP mods shipping svp_* shaders
# (svp_hooks_inside.h), NVG mods other than Beef's / Better Beef's (Real_NVGs_TEST:
# shader_param_5), and loose shader files in Anomaly\gamedata that win over every
# MO2 mod. Nothing is unticked or deleted here.
Head "Other mods and loose files that can break the pack"
$preflight = New-Object System.Collections.Generic.List[string]
if ($modlist) {
    foreach ($n in @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) })) {
        if (Is-PackMod $n) { continue }
        $r3 = "$modsDir\$n\gamedata\shaders\r3"
        if (-not (Test-Path -LiteralPath $r3 -PathType Container)) { continue }
        $svp = @(Get-ChildItem -LiteralPath $r3 -Filter 'svp_*' -File -ErrorAction SilentlyContinue | ForEach-Object Name)
        if ($svp.Count) { $preflight.Add("'$n' ships old bodycam/PiP shaders ($(($svp | Select-Object -First 3) -join ', ')). If the game shows a shader error, untick it.") }
        if ((Test-Path -LiteralPath "$r3\nightvision_gen_1.ps") -and $n -notlike "*Beef's NVG*") {
            $preflight.Add("'$n' replaces the night vision shaders. Only Beef's / Better Beef's NVGs are supported with the pack; if NVGs crash or look wrong, untick it.")
        }
    }
}
$loose = @(Get-ChildItem -LiteralPath "$anomaly\gamedata\shaders" -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like 'svp_*' -or $_.Name -like 'scope_*' })
# Model Drop: items_model_drop_physc_mre.ltx and items_model_drop_physc_newfddaanim.ltx
# define the same sections; ticked together in two mods = DLTX duplicate-section FATAL
# at start (Bisanch, v0.6). If one of the two is G.A.M.M.A.'s own "453- Items Model Drop"
# it is unticked (recorded: the uninstaller ticks it again); otherwise only a warning.
if ($modlist) {
    $owners = @{}
    foreach ($n in @($lines | Where-Object { $_.StartsWith('+') } | ForEach-Object { $_.Substring(1) })) {
        foreach ($f in 'items_model_drop_physc_mre.ltx', 'items_model_drop_physc_newfddaanim.ltx') {
            if (-not $owners[$f] -and (Test-Path -LiteralPath "$modsDir\$n\gamedata\configs\items\items\$f")) { $owners[$f] = $n }
        }
    }
    $a = $owners['items_model_drop_physc_mre.ltx']; $b = $owners['items_model_drop_physc_newfddaanim.ltx']
    if ($a -and $b -and $a -ne $b) {
        $kute = @($a, $b) | Where-Object { $_ -like '453- Items Model Drop*' } | Select-Object -First 1
        if ($kute) {
            Warn "'$a' and '$b' both define the Model Drop sections (DLTX FATAL at start). Unticking G.A.M.M.A.'s '$kute'; the uninstaller ticks it again."
            $dropNames[$kute] = $false
        } else {
            $preflight.Add("'$a' and '$b' both define the Model Drop sections (items_model_drop_physc_mre / _newfddaanim): the game stops at start with a DLTX duplicate. Untick one of them.")
        }
    }
}
if ($loose.Count) {
    $preflight.Add("$($loose.Count) loose shader file(s) in Anomaly\gamedata\shaders (e.g. $($loose[0].Name)), left by an old bodycam/PiP install. MO2 shows them as 'unmanaged' and they win over the pack: move them out of the Anomaly folder if you get shader errors.")
}
if ($preflight.Count) { foreach ($w in $preflight) { Warn $w } } else { Good "none found" }

# --- 7. tick + order in MO2 ---------------------------------------------
# modlist.txt: FIRST line = HIGHEST priority (= bottom of MO2's left pane).
$conflicts = @(
    'BODYCAM - PiP & 3DSS COMPATIBILITY PATCH*', 'Bodycam API Shim*',
    'DLSS FSR3 Compatibility Patch*', 'DLSS / FSR3 Compatibility Patch*', 'DLSS Compatibility*',
    'dlss binaries*compatibility*', 'dlss-binaries*', 'DLSS-FSR3 Compat Patch remerged - *',
    'Bodycam 0.3 DLSS Shader Merge - *', '*3DSS ZoomCalc*', 'Add-on - 3DSS zoom fix',
    'Bodycam Scope Effects Guard - *',   # old list-based guard; mod 6 replaces it (both drive scope_effects_enable)
    '3 - DLSS-FSR3 Compat Patch (m1RAGE5)', '5 - DX12 Frame Gen menu',
    'Bodycam-GAMMA-Patch*', 'Bodycam-Grass-Optimisation*',
    '3 - DLSS-FSR3 Compat Patch remerged (*',               # v0.5.0/v0.5.1 mod 3 (0.71); current one is skipped above
    'Add-on - Glossy Puddles Overhaul users (*',            # manual Glossy zips; the installer builds its own
    'Native Upscaling Binaries Compatibility Patch*',       # brodrigz 0.72+ raw patch: reverts our shaders
    '1 - Bodycam-GAMMA-Patch-1.1.0', '2 - Bodycam-Grass-Optimisation-4.1.0'
)
function Build-Modlist {
    $ours = @{}
    foreach ($n in $installed) { $ours[$n] = $true }
    $head = @(); $rest = @(); $script:unticked = @()
    $seenMod = $false
    foreach ($l in $lines) {
        if (-not $seenMod -and $l.StartsWith('#')) { $head += $l; continue }
        $seenMod = $true
        if ($l.Length -lt 2) { $rest += $l; continue }
        $name = $l.Substring(1)
        if ($ours.ContainsKey($name)) { continue }            # re-added below
        if ($dropNames.ContainsKey($name)) {                  # 3DSS step, old pack mods
            if ($dropNames[$name]) { $script:removedLines += $name }
            else { $rest += "-$name"; $script:unticked += $name }
            continue
        }
        if ($tickNames.ContainsKey($name)) { $rest += "+$name"; continue }
        if ($l.StartsWith('+') -and ($conflicts | Where-Object { $name -like $_ })) {
            $rest += "-$name"; $script:unticked += $name; continue
        }
        $rest += $l
    }
    $top = @()
    $was = Get-ModlistState $lines
    for ($i = $installed.Count - 1; $i -ge 0; $i--) {
        $n = $installed[$i]; $mark = '+'
        if ($n -like $texPattern) { $mark = $(if ($texResMigrate -or $was[$n] -ne '+') { '-' } else { '+' }) }
        $top += "$mark$n"
    }
    return , (@($head) + $top + $rest)
}
$newLines = $null; $removedLines = @()
if ($modlist) { $newLines = Build-Modlist }
elseif ($installed.Count -gt 0) {
    $todo.Add("Open MO2, tick these and drag them to the BOTTOM of the left pane, in this order:")
    foreach ($n in $installed) { $todo.Add("     $n") }
}

# --- 8. DX12 launch entry -----------------------------------------------
$exeTitle = 'Anomaly (DX12 + Frame Gen)'
$iniNew = $null
if (-not (Test-Path -LiteralPath $ini)) {
    $todo.Add("MO2: dropdown > <Edit...> > + > Add from file > Anomaly\bin\AnomalyDX12.exe, name it '$exeTitle'")
} else {
    try {
        $il = @([IO.File]::ReadAllLines($ini, $utf8))
        if (-not ($il -match 'Anomaly \(DX12 \+ Frame Gen\)')) {
            $exe = "$anomaly\bin\AnomalyDX12.exe" -replace '\\','/'
            $wd  = "$anomaly\bin" -replace '\\','/'
            $out = New-Object System.Collections.Generic.List[string]
            $inSection = $false; $added = $false
            foreach ($l in $il) {
                if ($l -match '^\[customExecutables\]') { $inSection = $true; $out.Add($l); continue }
                if ($inSection -and $l -match '^size=(\d+)\s*$') {
                    $n = [int]$Matches[1] + 1
                    $out.Add("size=$n")
                    foreach ($kv in @("arguments=", "binary=$exe", "hide=false", "ownicon=true", "steamAppID=",
                                      "title=$exeTitle", "toolbar=false", "workingDirectory=$wd")) {
                        $out.Add("$n\$kv")
                    }
                    $inSection = $false; $added = $true
                    continue
                }
                $out.Add($l)
            }
            if (-not $added) { throw "no [customExecutables] size= line" }
            $iniNew = ($out -join "`r`n") + "`r`n"
        }
    } catch {
        Warn "could not edit ModOrganizer.ini ($($_.Exception.Message))"
        $todo.Add("MO2: dropdown > <Edit...> > + > Add from file > Anomaly\bin\AnomalyDX12.exe, name it '$exeTitle'")
    }
}

# --- 9. video settings ---------------------------------------------------
# frame gen on by default only where it is native (RTX 40/50); RTX 20/30 can pick it
# in the menu through the unlock, but it may cost FPS there, so they opt in.
# Set on the first install only: a re-run never undoes your own choices
# (except MSAA, which must stay off and is checked on every run, below).
$want = [ordered]@{
    'r3_msaa'            = 'st_opt_off'
    'rs_v_sync'          = 'off'
    'r_upscaler'         = $(if ($rtx) { 'dlss' } else { 'fsr3' })
    'r_frame_generation' = $(if ($rtxFg) { 'dlss' } else { 'off' })
    'r__tex_res_budget_target' = '0'     # Texture Residency off by default (v0.7.1)
    'r__upscaler_camera_mv'    = '0'     # camera-MV fill off: it made the still image wobble (v0.7.1)
}
$ltx = "$anomaly\appdata\user.ltx"
$ltxRel = 'Anomaly\appdata\user.ltx'
$ltxSet = [ordered]@{}
if (Test-Path -LiteralPath $ltx) {
    $ltxNow = [IO.File]::ReadAllLines($ltx)
    foreach ($k in $want.Keys) {
        # MSAA is not a preference (the upscaler and the night vision shaders break with it):
        # it is put back off on every run. The other settings are set once.
        $e = $(if ($sr.Record) { $sr.Record.keys["$ltxRel|$k"] } else { $null })
        if ($k -eq 'r3_msaa') {
            $cur = $ltxNow | Where-Object { $_ -match '^r3_msaa\s' } | Select-Object -First 1
            # also when it is already off but not recorded yet, so the uninstaller knows the original line
            if ("$cur".Trim() -ne "r3_msaa $($want[$k])" -or -not ($e -and $null -ne $e.written)) { $ltxSet[$k] = $want[$k] }
            continue
        }
        if ($e -and $null -ne $e.written) { continue }
        $ltxSet[$k] = $want[$k]
    }
} else {
    Warn "no user.ltx yet (game never launched) - engine defaults apply"
    $todo.Add("In game: Settings > Video: MSAA off, VSync off, upscaler DLSS (RTX) or FSR")
}

# what the player is told about Texture Residency: shown before the install and again at the end
$texNote = @()
$texPackName = $installed | Where-Object { $_ -like $texPattern } | Select-Object -First 1
$texWas = $null
if ($ltxSet.Contains('r__tex_res_budget_target') -and $ltxNow) {
    $texWas = ($ltxNow | Where-Object { $_ -match '^r__tex_res_budget_target\s+(\S+)\s*$' } | Select-Object -First 1) -replace '^r__tex_res_budget_target\s+', ''
}
if ($texResMigrate -or $ltxSet.Contains('r__tex_res_budget_target')) {
    $texNote += "Texture Residency is OFF by default: r__tex_res_budget_target $(if ($texWas -and $texWas.Trim() -ne '0') { "was $($texWas.Trim()), now 0" } else { '0' })."
    if ($texPackName) {
        $texNote += "'$texPackName' is $(if ($modlist -and (Get-ModlistState $lines)[$texPackName] -eq '+') { 'now unticked' } else { 'left unticked' }) in MO2."
    }
    $texNote += "To opt in: tick '$(if ($texPackName) { $texPackName } else { '7 - Tex Residency Classes' })' in MO2, then MCM > Texture Residency (VRAM) > Manage VRAM on (or type r__tex_res_budget_target 80 in the console)."
}

# --- 10. checks: space, shader cache -------------------------------------
$cache = "$anomaly\appdata\shaders_cache"
$moveCache = (Test-Path -LiteralPath $cache) -and
             (-not $sr.Record -or -not $sr.Record.shaderCache.baseline -or $engineChange)
$need = 0
foreach ($p in $place) { $need += (Get-Item -LiteralPath $p.Src).Length }
foreach ($m in $modPlan) {
    if (-not $m.Zip) { continue }
    $z = [IO.Compression.ZipFile]::OpenRead($m.Zip)
    try { foreach ($en in $z.Entries) { $need += 2 * $en.Length } } finally { $z.Dispose() }   # unpacked once to stage, once in place
}
$need = [long]($need * 1.2)
$free = $null
try { $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($root))).AvailableFreeSpace } catch { }

# --- summary: nothing has been changed up to here -------------------------
Head "What I will do"
$replaceN = 0; $newN = 0; $sameN = 0
foreach ($p in $place) {
    $d = Get-PlanPath $p.Rel
    if (-not (Test-Path -LiteralPath $d)) { $newN++ } elseif ((Get-Sha $d) -eq (Get-Sha $p.Src)) { $sameN++ } else { $replaceN++ }
}
if ($inst.Split) { Say "  game folders: Anomaly $anomaly, G.A.M.M.A. (MO2) $gamma" }
else { Say "  game folder : $root" }
Say "  engine files: $newN new, $replaceN replaced (yours are moved to $root\.slopray\backup first), $sameN already up to date"
Say "  MO2 mods    : $($installed -join ', ')"
if ($leftovers.Count) { Say "  removing old Slop-Ray mods: $($leftovers -join ', ')" }
if ($modlist) {
    Say "  MO2 profile : $(Split-Path (Split-Path $modlist -Parent) -Leaf) - ticks the mods above at the bottom"
    if ($unticked.Count) { Say "                unticks: $($unticked -join ', ')" }
}
if ($sssRevert) {
    Say "  SSS24 found : switching back to SSS 23.5 (uninstall brings SSS24 back)"
    Say "                untick $(($sssRevert.Mods | ForEach-Object { "'$_'" }) -join ', '), tick '$sss23Name'"
    Say "                restore $($sssRevert.Restore.Count) GAMMA patch files, move $($sssRevert.Dlls.Count) loose Streamline DLLs to the backup"
}
if ($foreignDb0.Count) { Say "  modded exes : unticks $(($foreignDb0 | ForEach-Object { "'$_'" }) -join ', ') (db0 for a different exe)" }
if ($iniNew) { Say "  MO2 launch  : adds '$exeTitle'" }
if ($ltxSet.Count) { Say "  user.ltx    : $(($ltxSet.Keys | ForEach-Object { "$_ $($ltxSet[$_])" }) -join ', ')" }
if ($moveCache) { Say "  shader cache: moved aside (the game rebuilds it on first launch)" }
foreach ($t in $texNote) { Say "  $t" }
if ($optiNote) { Say "  $optiNote" }
Say "  disk space  : needs about $([math]::Ceiling($need / 1MB)) MB$(if ($free) { ", $([math]::Floor($free / 1MB)) MB free" })"
if ($free -and $free -lt $need) { Bad "not enough free space on $([IO.Path]::GetPathRoot($root)) - free some and run again"; Pause-End 1 }
if ($fail -gt 0) { Bad "fix the red lines above first - nothing was changed"; Pause-End 1 }
if ($DryRun) {
    Say ""
    Say "  DRY RUN COMPLETE - nothing was changed"
    Pause-End 0
}
Say ""
if (-not (Confirm-Go "Install now?")) { Say "  Cancelled - nothing was changed."; Pause-End 1 }

# --- install: every change below is recorded and can be undone ------------
try {
    Start-Run $sr 'install' $PackVersion
} catch {
    Bad "can't write in $root ($($_.Exception.Message))."
    Say "  If the game is under Program Files, right-click the folder > Properties > Security"
    Say "  and give your user 'Modify', or move the game to a folder like C:\Games."
    Pause-End 1
}
$counts = @{}
function Put ($rel, $src, [switch]$PackMod, [switch]$Keep) {
    $a = Install-OwnedFile $sr $rel $src -PackMod:$PackMod -Keep:$Keep
    $script:counts[$a] = 1 + [int]$script:counts[$a]
}
try {
    Head "Installing engine files"
    $sets = $place | Group-Object { $_.Set }
    foreach ($g in $sets) {
        $script:counts = @{}
        foreach ($p in $g.Group) { Put $p.Rel $p.Src }
        Good "$($g.Name) - $($g.Count) files hash-verified ($(($counts.Keys | Sort-Object | ForEach-Object { "$($counts[$_]) $_" }) -join ', '))"
    }
    if ($optiIni) {
        # pack ini ships DLSS 5 off; turn it on in [DlssNr] only
        $lines6 = [IO.File]::ReadAllLines($optiIni)
        $sec = ''
        for ($i = 0; $i -lt $lines6.Count; $i++) {
            $t = $lines6[$i].Trim()
            if ($t -match '^\[(.+)\]$') { $sec = $Matches[1]; continue }
            if ($sec -eq 'DlssNr' -and $t -match '^Enabled\s*=') { $lines6[$i] = 'Enabled=true'; break }
        }
        $stIni = "$($sr.Run.Dir)\stage\OptiScaler.ini"
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $stIni))
        [IO.File]::WriteAllLines($stIni, $lines6, $utf8)
        Put 'Anomaly\bin\OptiScaler.ini' $stIni
        Good "DLSS 5 switched on in OptiScaler.ini"
    }
    if ($sssRevert) {
        Head "Switching SSS24 back to SSS 23.5"
        $moved = 0
        foreach ($d in $sssRevert.Dlls) {
            $a = Remove-ForeignFile $sr $d
            if ($a -eq 'moved') { $moved++ } elseif ($a -eq 'kept') { Warn "left in place (a different copy is already in the backup): $d" }
        }
        Good "$moved loose Streamline DLLs moved to $($sr.Dir)\backup\Anomaly\bin"
        $script:counts = @{}
        foreach ($p in $sssRevert.Restore) { Put $p.Rel $p.Src }
        Good "$($sssRevert.Restore.Count) GAMMA patch files put back in Anomaly\gamedata"
    }
    if ($doOpti -and (Test-Path -LiteralPath "$anomaly\bin\OptiScaler\nvfp4")) {
        # left behind by the 0.7.x packs; F5 no longer uses it (F5 DOES use nvngx.dll_dlssnr.dll)
        [void](Remove-OwnedTree $sr 'Anomaly\bin\OptiScaler\nvfp4' -RemoveTop)
        Say "  removed what was ours in obsolete OptiScaler\nvfp4"
    }

    Head "Unpacking MO2 mods"
    foreach ($m in $modPlan) {
        $stage = "$($sr.Run.Dir)\stage\mods\$($m.Name)"
        [void][IO.Directory]::CreateDirectory($stage)
        if ($m.Zip) { [IO.Compression.ZipFile]::ExtractToDirectory($m.Zip, $stage) }
        else {
            [void][IO.Directory]::CreateDirectory("$stage\gamedata\shaders\r3")
            [IO.File]::WriteAllText("$stage\gamedata\shaders\r3\deffer_impl_flat.ps", $glossyText, $utf8)   # no BOM: fxc rejects it
            [IO.File]::WriteAllText("$stage\meta.ini", $glossyMeta, $utf8)
        }
        [IO.File]::WriteAllText("$stage\slopray-mod.json", "{ `"mod`": `"$($m.Name -replace '["\\]', '_')`", `"pack`": `"$PackVersion`" }`r`n", $utf8)
        $keep = @{}
        $script:counts = @{}
        foreach ($f in Get-ChildItem -LiteralPath $stage -Recurse -File) {
            $rel = "GAMMA\mods\$($m.Name)\" + $f.FullName.Substring($stage.Length).TrimStart('\')
            $keep[$rel] = $true
            Put $rel $f.FullName -PackMod
        }
        # files of ours from an older version of this mod that this one no longer ships
        [void](Remove-OwnedTree $sr "GAMMA\mods\$($m.Name)" -Except $keep)
        Good "$($m.Name) ($(($counts.Keys | Sort-Object | ForEach-Object { "$($counts[$_]) $_" }) -join ', '))"
    }
    foreach ($l in $leftovers) {
        if (Remove-OwnedTree $sr "GAMMA\mods\$l" -UnknownToRecovery -RemoveTop) { Good "removed old $l" }
        else { $dropNames[$l] = $false; Warn "old $l could not be fully removed - unticked instead" }
    }

    if ($modlist) {
        Head "Ticking the mods in MO2"
        $removedLines = @()
        $newLines = Build-Modlist
        foreach ($u in $unticked) { Say "  unticked old/conflicting: $u" }
        foreach ($r in $removedLines) { Say "  removed from list: $r" }
        $mlRel = Get-Rel $sr $modlist
        if (-not $sr.Record.modlist[$mlRel]) { $sr.Record.modlist[$mlRel] = @{} }
        $rec = $sr.Record.modlist[$mlRel]
        $before = Get-ModlistState $lines
        # older installers kept the very first modlist as modlist.txt.old: that is the real original
        $orig = $before
        if ($sr.WasNew -and (Test-Path -LiteralPath "$modlist.old")) { $orig = Get-ModlistState ([IO.File]::ReadAllLines("$modlist.old", $utf8)) }
        $after = Get-ModlistState $newLines
        $names = @($before.Keys) + @($after.Keys) | Sort-Object -Unique
        foreach ($n in $names) {
            # also lines an older installer changed (they differ from the .old original)
            if ($before[$n] -eq $after[$n] -and $orig[$n] -eq $after[$n] -and -not $installed.Contains($n)) { continue }
            if (-not $rec[$n]) { $rec[$n] = @{ baseline = $orig[$n] } }
            $rec[$n].written = $after[$n]
        }
        Set-TextFile $sr $mlRel ((@($newLines) -join "`r`n") + "`r`n")
        Good "$(@($newLines | Where-Object { $_ -match '^\+' -and $installed.Contains($_.Substring(1)) }).Count) mods ticked at the bottom of MO2's left pane"
    }

    Head "MO2 launch entry '$exeTitle'"
    if ($iniNew) {
        Set-TextFile $sr 'GAMMA\ModOrganizer.ini' $iniNew
        $sr.Record.exe = @{ file = 'GAMMA\ModOrganizer.ini'; title = $exeTitle; binary = ("$anomaly\bin\AnomalyDX12.exe" -replace '\\','/'); written = $true }
        Good "added"
    } elseif (Test-Path -LiteralPath $ini) {
        Good "already there"
        # added by an older installer? (its first ModOrganizer.ini.old has no such entry)
        if ($sr.WasNew -and (Test-Path -LiteralPath "$ini.old") -and
            -not ([IO.File]::ReadAllText("$ini.old", $utf8) -match 'Anomaly \(DX12 \+ Frame Gen\)')) {
            $sr.Record.exe = @{ file = 'GAMMA\ModOrganizer.ini'; title = $exeTitle; binary = ("$anomaly\bin\AnomalyDX12.exe" -replace '\\','/'); written = $true }
        }
    }

    Head "Video settings (user.ltx)"
    if ($ltxSet.Count) {
        $ul = New-Object System.Collections.Generic.List[string]
        $ul.AddRange([string[]][IO.File]::ReadAllLines($ltx))
        $origLtx = $ul.ToArray()
        if ($sr.WasNew -and (Test-Path -LiteralPath "$ltx.old")) { $origLtx = [IO.File]::ReadAllLines("$ltx.old") }
        foreach ($k in $ltxSet.Keys) {
            $m = @($origLtx | Where-Object { $_ -match "^$([regex]::Escape($k))\s" })
            $baseLine = $(if ($m.Count) { $m[0] } else { $null })     # $null = the key was not there
            $idx = -1
            for ($i = 0; $i -lt $ul.Count; $i++) { if ($ul[$i] -match "^$([regex]::Escape($k))\s") { $idx = $i; break } }
            $v = "$k $($ltxSet[$k])"
            if ($idx -ge 0) { $ul[$idx] = $v } else { $ul.Add($v) }
            $ek = "$ltxRel|$k"
            if (-not $sr.Record.keys[$ek]) { $sr.Record.keys[$ek] = @{ file = $ltxRel; key = $k; baseline = $baseLine } }
            $sr.Record.keys[$ek].written = $v
            Good $v
        }
        Set-TextFile $sr $ltxRel (($ul -join "`r`n") + "`r`n")
    } elseif (Test-Path -LiteralPath $ltx) { Good "already set by an earlier install - your own changes are kept" }

    Head "Shader cache"
    if ($moveCache) {
        try {
            [void](Resolve-Rel $sr 'Anomaly\appdata\shaders_cache')
            if (-not $sr.Record.shaderCache.baseline) {
                $to = "$($sr.Dir)\shaders_cache_before_slopray"
                $sr.Record.shaderCache.baseline = $to
            } else {
                $to = "$($sr.Run.Dir)\shaders_cache_old"
                $sr.Record.shaderCache.stalePending = $to
            }
            Move-DirLogged $sr $cache $to
            Good "moved aside to $to"
        } catch { Warn "could not move the shader cache ($($_.Exception.Message)) - delete Anomaly\appdata\shaders_cache by hand" }
    } else { Good "nothing to clear" }

    Head "Uninstaller"
    $tool = "$($sr.Dir)\tool"
    [void][IO.Directory]::CreateDirectory($tool)
    foreach ($f in 'SlopRay.psm1', 'uninstall.ps1', 'cleanup_backups.ps1', 'catalogue.json', 'UNINSTALL - Slop-Ray Engine.bat', 'CLEAN UP BACKUPS - Slop-Ray Engine.bat') {
        if (Test-Path -LiteralPath "$pack\$f") { Copy-Item -LiteralPath "$pack\$f" "$tool\$f" -Force }
    }
    # a game on a drive root (C:\GAMMA): Windows lets a normal user make folders there, not files.
    # The same two .bat files are in .slopray\tool, so the root copies are skipped then.
    $rootTest = "$root\.sr-write-test"
    $rootWritable = try { [IO.File]::WriteAllText($rootTest, ''); [IO.File]::Delete($rootTest); $true } catch { $false }
    if ($rootWritable) {
        foreach ($b in 'UNINSTALL - Slop-Ray Engine.bat', 'CLEAN UP BACKUPS - Slop-Ray Engine.bat') {
            if (Test-Path -LiteralPath "$pack\$b") { Put $b "$pack\$b" -Keep }
        }
        Good "'UNINSTALL - Slop-Ray Engine.bat' is in $root"
    } else {
        Good "'UNINSTALL - Slop-Ray Engine.bat' is in $tool (Windows does not allow new files in $root)"
    }

    Head "Checking the install"
    # only what THIS run placed: a file from an earlier run that this one skipped
    # (DLSS 5 last time, or OptiScaler not needed on this GPU) is not this run's job
    function Get-VerifyProblems {
        foreach ($rel in @($sr.Run.Placed.Keys)) {
            $want = $sr.Record.files[$rel].installedHash
            $p = Resolve-Rel $sr $rel
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { "$rel is missing"; continue }
            $got = Get-Sha $p
            if ($got -ne $want) { "$rel is different (expected $($want.Substring(0,12)), found $($got.Substring(0,12)))" }
        }
    }
    $problems = @(Get-VerifyProblems)
    if ($problems.Count) { Start-Sleep -Seconds 2; $problems = @(Get-VerifyProblems) }   # one more look: antivirus scans settle
    if ($problems.Count) {
        foreach ($p in $problems) { Warn $p }
        Say "  Something changed these files right after they were copied. Usually an antivirus"
        Say "  (quarantining OptiScaler's dxgi.dll is common) or a game / MO2 still running."
        throw "$($problems.Count) installed file(s) did not verify"
    }
    Good "every file placed in this run matches its SHA-256 ($($sr.Run.Placed.Count) files)"

    # the previous moved-aside cache (from an older engine) is not kept: only
    # the one from before the first install and the newest
    $old = $sr.Record.shaderCache.stale
    if ($sr.Record.shaderCache.stalePending) { $sr.Record.shaderCache.stale = $sr.Record.shaderCache.stalePending; $sr.Record.shaderCache.Remove('stalePending') }
    if ($legacy3dss) { $sr.Record.legacy3dss = @{ backup = 'GAMMA\3DSS_backup'; mod = $(if ($tdss) { $tdss.Name } else { '' }) } }
    $sr.Record.texResOff = $true
    Complete-Run $sr 'installed'
    if ($old -and $old -ne $sr.Record.shaderCache.stale -and $old.StartsWith("$($sr.Dir)\runs\") -and (Test-Path -LiteralPath $old)) {
        # a shader cache we moved inside our own .slopray\runs folder: regenerated data
        Get-ChildItem -LiteralPath $old -Recurse -File -Force | ForEach-Object { [IO.File]::Delete($_.FullName) }
        Remove-EmptyDirs $null $old -IncludeTop
    }
} catch {
    Bad "install failed: $($_.Exception.Message)"
    Say "  undoing what this run changed..."
    try {
        $problems = Undo-Run $sr $sr.Run.Id
        if ($problems.Count) {
            foreach ($p in $problems) { Warn $p }
            Bad "undo left $($problems.Count) thing(s) to check (above). Nothing was deleted: your originals are in $($sr.Dir)\backup"
        } else { Good "undone - your files are as they were before this run" }
    } catch {
        Bad "undo did not finish: $($_.Exception.Message)"
        Say "  Nothing was deleted. Your originals are in $($sr.Dir)\backup."
        Say "  Run the installer again: it will offer to finish undoing this run."
    }
    Pause-End 1
}

# --- done ----------------------------------------------------------------
Say ""
Say "==================================================================="
if ($fail -gt 0)  { Write-Host "  FINISHED WITH $fail PROBLEM(S) - read the red lines" -ForegroundColor Red }
else              { Write-Host "  INSTALLED" -ForegroundColor Green }
Say "==================================================================="
Say ""
# what actually happened, so "the installer didn't do X" can be checked from a screenshot
Say "SUMMARY:"
Say "  GPU: $(if ($gpu) { $gpu } else { 'unknown' })"
if ($optiNote) { Say "  $optiNote" }
$addOns = @($installed | Where-Object { $_ -like 'Add-on - *' })
Say "  add-ons: $(if ($addOns.Count) { $addOns -join ', ' } else { 'none needed' })"
Say "  MO2 mods ticked by installer: $(if ($modlist) { 'yes' } else { 'NO (tick them by hand, see below)' })"
if ($sssRevert) { Say "  SSS24 found: switched back to SSS 23.5 ($($sssRevert.Mods -join ', ') unticked). The uninstaller brings SSS24 back." }
foreach ($t in $texNote) { Say "  $t" }
Say "  your replaced files: $($sr.Dir)\backup (kept until you remove them)"
foreach ($n in $sr.Notes) { Warn $n }
if ($sr.Notes.Count) { Say "  recovery folder: $($sr.Dir)\recovery" }
Say "  to remove Slop-Ray again: 'UNINSTALL - Slop-Ray Engine.bat' in your GAMMA folder"
Say "  if the game crashes: send Anomaly\appdata\logs\xray_<name>.log and the"
Say "  newest file in %APPDATA%\QUARK-ENGINE\ERROR"
Say ""
Say "LEFT TO DO:"
$k = 1
foreach ($t in $todo) { if ($t.StartsWith(' ')) { Say "     $t" } else { Say "  $k. $t"; $k++ } }
Say "  $k. Model Drop 15 installed + ticked in MO2? If not: README step 1."; $k++
Say "  $k. NVIDIA App: Smooth Motion OFF for Anomaly (else DX12 crashes)."; $k++
Say "  $k. MO2 dropdown: pick 'Anomaly (DX12 + Frame Gen)' > Run."
Say "     First launch rebuilds shaders, looks frozen a few minutes. Wait."
Say ""
Say "  Optional: Texture Residency is off by default. If you stutter: tick '7 - Tex Residency Classes' in MO2, then MCM > Texture Residency (VRAM) > Manage VRAM on."
Say ""
Pause-End $(if ($fail -gt 0) { 1 } else { 0 })
