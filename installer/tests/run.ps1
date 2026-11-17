# ===========================================================================
#  Installer / uninstaller tests on FAKE GAMMA folders under %TEMP%.
#  Never touches a real install: every run gets -GamePath to its own fake.
#  Folder names carry spaces, brackets, &, !, % and a non-ASCII letter.
#     powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1 [-Only S7] [-Keep]
# ===========================================================================
param([string]$Only, [switch]$Keep)
$ErrorActionPreference = 'Stop'
$src  = Split-Path -Parent $PSScriptRoot
$base = "$env:TEMP\sr_tests_$(Get-Date -Format 'HHmmss')"
$weird = "S.T.A.L.K.E.R. GAMMA (" + [char]0xFC + " & !) [x] 100%"
$utf8 = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$env:SLOPRAY_TEST_NO_PROCESS_CHECK = '1'
$script:passed = 0; $script:failed = New-Object System.Collections.Generic.List[string]

function W ($path, $text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}
function T ($path) { [IO.File]::ReadAllText($path, $utf8) }
function Sha ($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Check ($cond, $what) {
    if ($cond) { $script:passed++ } else { $script:failed.Add("$($script:scenario): $what"); Write-Host "    FAIL: $what" -ForegroundColor Red }
}

# --- fixtures -----------------------------------------------------------------
function New-Zip ($zip, [hashtable]$files) {
    $tmp = "$zip.d"
    foreach ($k in $files.Keys) { W "$tmp\$k" $files[$k] }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $zip))
    [IO.Compression.ZipFile]::CreateFromDirectory($tmp, $zip)
    Remove-Item -LiteralPath $tmp -Recurse -Force      # test scratch only
}

function New-Pack ($dir) {
    foreach ($f in 'install.ps1', 'uninstall.ps1', 'cleanup_backups.ps1', 'SlopRay.psm1',
                   'UNINSTALL - Slop-Ray Engine.bat', 'CLEAN UP BACKUPS - Slop-Ray Engine.bat') {
        [void][IO.Directory]::CreateDirectory($dir)
        Copy-Item -LiteralPath "$src\$f" "$dir\$f"
    }
    W "$dir\STEP 1 - Engine\bin\AnomalyDX11AVX.exe" 'SR dx11 v0.5.2'
    W "$dir\STEP 1 - Engine\bin\msvcp140.dll" 'vc runtime'
    W "$dir\STEP 1 - Engine\db\mods\00_modded_exes_gamedata.db0" 'SR db0 v0.5.2'
    W "$dir\STEP 7 - Frame generation\bin\AnomalyDX12.exe" 'SR dx12 v0.5.2'
    W "$dir\STEP 7 - Frame generation\bin\streamline\sl.common.dll" 'sl common'
    W "$dir\STEP 6 - OptiScaler\dxgi.dll" 'optiscaler dll'
    W "$dir\STEP 6 - OptiScaler\OptiScaler.ini" "[DlssNr]`r`nEnabled=false`r`n"
    W "$dir\STEP 6 - OptiScaler\LICENSE" 'license'
    W "$dir\STEP 6 - OptiScaler\Licenses\a.txt" 'license a'
    W "$dir\STEP 6 - OptiScaler\README.md" 'readme'
    W "$dir\STEP 6 - OptiScaler\OptiScaler\libxess.dll" 'xess'
    W "$dir\STEP 6 - OptiScaler\nvngx_dlssnr.dll" 'dlss 5 model'
    # another F5 version: only the files that differ, in "STEP 6\F5 <version>"
    W "$dir\STEP 6 - OptiScaler\F5 0.1.38\dxgi.dll" 'optiscaler 0138'
    W "$dir\STEP 6 - OptiScaler\F5 0.1.38\OptiScaler.ini" "[DlssNr]`r`nEnabled=false`r`n[FrameGen]`r`nFGOutput=auto`r`n"
    New-Zip "$dir\STEP 2 - MO2 mods\1 - Test Patch.zip" @{ 'gamedata\configs\a.ltx' = 'patch a'; 'meta.ini' = "[General]`r`nversion=1`r`n" }
    New-Zip "$dir\STEP 2 - MO2 mods\3 - Test Compat (0.721).zip" @{ 'gamedata\shaders\r3\x.ps' = 'compat 0.721' }
    New-Zip "$dir\STEP 3 - Optional\Add-on - stock Atmospherics (no RC7).zip" @{ 'gamedata\shaders\r3\ssfx.h' = 'stock atmos' }
    New-Zip "$dir\STEP 3 - Optional\Add-on - Anti-Lag for GAMMA users.zip" @{ 'gamedata\scripts\al.script' = 'anti lag' }
    # catalogue: this pack's files + an "old release" (v0.5.1)
    $old = "$dir.oldrelease"
    W "$old\dx12" 'SR dx12 v0.5.1'
    W "$old\dx11" 'SR dx11 v0.5.1'
    W "$old\compat" 'compat 0.71'
    $hashes = @{}
    foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File) { $hashes[(Sha $f.FullName)] = $f.Name }
    foreach ($f in Get-ChildItem -LiteralPath $old -Recurse -File) { $hashes[(Sha $f.FullName)] = $f.Name }
    foreach ($z in Get-ChildItem -LiteralPath $dir -Recurse -Filter *.zip) {
        $a = [IO.Compression.ZipFile]::OpenRead($z.FullName)
        foreach ($en in $a.Entries) {
            $ms = New-Object IO.MemoryStream; $s = $en.Open(); $s.CopyTo($ms); $s.Close()
            $sha = [Security.Cryptography.SHA256]::Create()
            $hashes[(($sha.ComputeHash($ms.ToArray()) | ForEach-Object { $_.ToString('X2') }) -join '')] = $en.FullName
        }
        $a.Dispose()
    }
    $cat = @{ releases = @('test'); modNames = @('1 - Test Patch', '3 - Test Compat (0.71)', '3 - Test Compat (0.721)',
              'Add-on - stock Atmospherics (no RC7)', 'Add-on - Anti-Lag for GAMMA users'); hashes = $hashes }
    W "$dir\catalogue.json" ($cat | ConvertTo-Json -Depth 4)
}

# SSFX_ScreenSpaceReflections as SSS 23.5, pre-23.5 SSS, and Atmos/Glossy (built for 23.5) declare it
$sig235   = 'void SSFX_ScreenSpaceReflections(float2 tc, float4 P, float3 N, float4 gloss, inout float4 color, float HudMask, inout float2 noise, inout float hitdepth, uint iSample : SV_SAMPLEINDEX)'
$sigOld   = 'void SSFX_ScreenSpaceReflections(float2 tc, float4 P, float3 N, float gloss, inout float3 color, uint iSample : SV_SAMPLEINDEX)'
$sigAtmos = 'void SSFX_ScreenSpaceReflections(float2 tc, float4 P, float3 N, float4 gloss, float hemi, inout float4 color, float HudMask, inout float2 noise, inout float hitdepth, uint iSample : SV_SAMPLEINDEX)'

function New-Gamma ($root) {
    W "$root\Anomaly\bin\AnomalyDX11AVX.exe" 'GAMMA original dx11'
    W "$root\Anomaly\bin\other.dll" 'unrelated dll'
    W "$root\Anomaly\db\mods\00_modded_exes_gamedata.db0" 'GAMMA original db0'
    W "$root\Anomaly\db\other.db0" 'unrelated db'
    W "$root\Anomaly\appdata\user.ltx" "r3_msaa st_opt_4x`r`nrs_v_sync on`r`nmouse_sens 0.12`r`n"
    W "$root\Anomaly\appdata\shaders_cache\r3\x.bin" 'cache'
    W "$root\GAMMA\ModOrganizer.ini" "[General]`r`nselected_profile=@ByteArray(Test Profile)`r`n[customExecutables]`r`nsize=1`r`n1\title=Anomaly (DX11-AVX)`r`n1\binary=C:/x/AnomalyDX11AVX.exe`r`n[Settings]`r`nfoo=bar`r`n"
    W "$root\GAMMA\profiles\Test Profile\modlist.txt" "# This file was automatically generated by Mod Organizer.`r`n+My Own Mod`r`n+410- 3DSS for GAMMA`r`n+Bodycam-GAMMA-Patch-2.0.1`r`n-Disabled Mod`r`n+Anti_Lag_for_GAMMA 1.2`r`n+190- Screen Space Shaders 23 - Ascii1457`r`n"
    W "$root\GAMMA\mods\190- Screen Space Shaders 23 - Ascii1457\gamedata\shaders\r3\screenspace_reflections.h" $sig235
    W "$root\GAMMA\profiles\Other\modlist.txt" "+My Own Mod`r`n"
    W "$root\GAMMA\mods\My Own Mod\gamedata\a.ltx" 'mine'
    W "$root\GAMMA\mods\410- 3DSS for GAMMA\gamedata\configs\mod_system_3dss_dummy_scopes.ltx" '3dss 4.17'
    W "$root\GAMMA\mods\410- 3DSS for GAMMA\gamedata\configs\my_custom.ltx" 'my custom 3dss file'
    W "$root\GAMMA\mods\Bodycam-GAMMA-Patch-2.0.1\gamedata\b.ltx" 'bodycam'
    W "$root\GAMMA\mods\Anti_Lag_for_GAMMA 1.2\gamedata\c.ltx" 'antilag'
    W "$root\GAMMA\mods\Disabled Mod\gamedata\d.ltx" 'disabled'
}

function Snap ($root) {
    $h = @{}
    foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $rel = $f.FullName.Substring($root.Length + 1)
        if ($rel -like '.slopray\*') { continue }
        $h[$rel] = Sha $f.FullName
    }
    $h
}
function Compare-Snap ($a, $b) {
    $d = @()
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k)) { $d += "-$k" } elseif ($a[$k] -ne $b[$k]) { $d += "~$k" } }
    foreach ($k in $b.Keys) { if (-not $a.ContainsKey($k)) { $d += "+$k" } }
    , $d
}

function Run ($script, $root, $extra = @()) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -GamePath $root -Yes @extra 2>&1 | Out-String
    $script:lastOut = $out
    $script:lastCode = $LASTEXITCODE
    if ($env:SR_TEST_VERBOSE) { Write-Host $out }
    $LASTEXITCODE
}
# no -GamePath: the installer has to find the game itself (SLOPRAY_TEST_SEARCH_ONLY limits where)
function RunFind ($script, $extra = @()) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Yes @extra 2>&1 | Out-String
    $script:lastOut = $out
    $script:lastCode = $LASTEXITCODE
    if ($env:SR_TEST_VERBOSE) { Write-Host $out }
    $LASTEXITCODE
}
# MO2 writes paths as @ByteArray(...): \\ for a backslash, \xHH for each non-ASCII UTF-8 byte
function ConvertTo-QtValue ([string]$s) {
    $o = ''
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') { $o += '\\' }
        elseif ([int]$ch -lt 128) { $o += $ch }
        else { foreach ($b in $utf8.GetBytes([string]$ch)) { $o += '\x' + $b.ToString('x2') } }
    }
    "@ByteArray($o)"
}
$gpu = @('-GpuName', 'NVIDIA GeForce RTX 3060')
function Install ($s, $extra = @()) { Run "$($s.Pack)\install.ps1" $s.Root ($gpu + $extra) }
function Uninstall ($s) { Run "$($s.Root)\.slopray\tool\uninstall.ps1" $s.Root }
function Rec ($s) { Get-Content -LiteralPath "$($s.Root)\.slopray\record.json" -Raw -Encoding UTF8 | ConvertFrom-Json }

function New-Scenario ($name) {
    $script:scenario = $name
    Write-Host "  $name" -ForegroundColor Cyan
    $d = "$base\$name"
    $s = @{ Root = "$d\$weird"; Pack = "$d\pack [v0.5.2] & co" }
    New-Pack $s.Pack
    New-Gamma $s.Root
    $s
}
function Show-OnFail ($ok) { if (-not $ok) { Write-Host $script:lastOut } }

# An SSS24 setup: a player who followed the SSS24 tutorial (steps 4 to 9) on top of
# New-Gamma. See tests\SSS_REVERT_TEST_PLAN.md.
$sl      = 'sl.common.dll', 'sl.dlss.dll', 'sl.interposer.dll', 'sl.pcl.dll', 'sl.reflex.dll'
$sss23   = '190- Screen Space Shaders 23 - Ascii1457'
$sss24   = 'SSS24 my install'
$mt      = 'STALKER-Anomaly-modded-exes-MT-TEST_2026.10.11'
$patches = "GAMMA\.Grok's Modpack Installer\G.A.M.M.A\modpack_patches"
$mlRel   = 'GAMMA\profiles\Test Profile\modlist.txt'
function New-Sss24Setup ($s, [switch]$NoSss23, [switch]$OldSss23, [switch]$NoPatches) {
    $r = $s.Root; $m = "$r\GAMMA\mods"
    if ($NoSss23) { Remove-Item -LiteralPath "$m\$sss23" -Recurse -Force }     # test scratch only
    elseif ($OldSss23) { W "$m\$sss23\gamedata\shaders\r3\screenspace_reflections.h" $sigOld }
    W "$m\$sss24\gamedata\shaders\r3\screenspace_materials.h" 'sss24 materials'
    W "$m\$sss24\gamedata\scripts\demonized_sss_imgui.script" 'sss24 imgui'
    W "$m\$sss24\db\mods\ssfx_rain_footsteps.db0" 'sss24 footsteps db'
    W "$m\$mt\db\mods\00_modded_exes_gamedata.db0" 'demonized db0 2026.10.11'
    W "$r\Anomaly\bin\AnomalyDX11AVX.exe" 'SSS24 exe'
    foreach ($d in $sl) { W "$r\Anomaly\bin\$d" "sss24 sl 2.11.1 $d" }
    W "$r\Anomaly\bin\nvngx_dlss.dll" 'sss24 dlss 310.6'
    W "$r\Anomaly\gamedata\configs\x.ltx" 'player config'
    if (-not $NoPatches) {
        W "$r\$patches\gamedata\configs\x.ltx" 'gamma config'
        W "$r\$patches\gamedata\shaders\r3\combine_2_naa.ps" 'gamma combine'
        W "$r\$patches\gamedata\scripts\gamma_patch.script" 'gamma script'
        W "$r\$patches\bin\AnomalyDX11.exe" 'gamma dx11 non-avx'
    }
    W "$r\$mlRel" ("# This file was automatically generated by Mod Organizer.`r`n+My Own Mod`r`n+$mt`r`n+$sss24`r`n-$sss23`r`n" +
                   "+410- 3DSS for GAMMA`r`n+Bodycam-GAMMA-Patch-2.0.1`r`n-Disabled Mod`r`n+Anti_Lag_for_GAMMA 1.2`r`n")
    W "$r\GAMMA\profiles\Other\modlist.txt" "+My Own Mod`r`n+$sss24`r`n"
}
function ML ($s) { [IO.File]::ReadAllLines("$($s.Root)\$mlRel") }
# adds a mod line right after the header of the active profile
function Add-ModLine ($s, $line) {
    $ml = @(ML $s)
    W "$($s.Root)\$mlRel" (((@($ml[0], $line) + $ml[1..($ml.Count - 1)]) -join "`r`n") + "`r`n")
}

# allowed to differ after a full uninstall: the shader cache (moved into
# .slopray, the game rebuilds it) and the two tool .bat files we leave behind
function Assert-BackToOriginal ($pre, $root, $what) {
    $d = Compare-Snap $pre (Snap $root)
    $d = @($d | Where-Object { $_ -notlike '?Anomaly\appdata\shaders_cache\*' -and
                               $_ -ne '+UNINSTALL - Slop-Ray Engine.bat' -and $_ -ne '+CLEAN UP BACKUPS - Slop-Ray Engine.bat' })
    Check ($d.Count -eq 0) "$what (diff: $($d -join ', '))"
}

# --- scenarios -------------------------------------------------------------
$scenarios = [ordered]@{}

$scenarios['S0_dry_run'] = {
    $s = New-Scenario 'S0_dry_run'
    $pre = Snap $s.Root
    $c = Install $s @('-DryRun')
    Check ($c -eq 0) "dry run exit 0 (got $c)"
    Check ((Compare-Snap $pre (Snap $s.Root)).Count -eq 0) "dry run changed nothing"
    Check (-not (Test-Path -LiteralPath "$($s.Root)\.slopray")) "dry run made no .slopray folder"
}

$scenarios['S1_fresh_install'] = {
    $s = New-Scenario 'S1_fresh_install'
    $pre = Snap $s.Root
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $r = $s.Root
    Check ((T "$r\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'SR dx11 v0.5.2') "dx11 exe installed"
    Check ((T "$r\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'GAMMA original dx11') "original dx11 in backup"
    Check ((T "$r\.slopray\backup\Anomaly\db\mods\00_modded_exes_gamedata.db0") -eq 'GAMMA original db0') "original db0 in backup"
    Check (-not (Get-ChildItem -LiteralPath $r -Recurse -Filter *.old -Force)) "no .old files made"
    Check (-not (Test-Path -LiteralPath "$r\Anomaly\bin\LICENSE") -and -not (Test-Path -LiteralPath "$r\Anomaly\bin\Licenses")) "STEP 6 licences not copied into bin"
    Check ((T "$r\Anomaly\bin\dxgi.dll") -eq 'optiscaler dll') "OptiScaler installed (RTX 3060)"
    Check (Test-Path -LiteralPath "$r\GAMMA\mods\1 - Test Patch\slopray-mod.json") "pack mod marker written"
    $ml = [IO.File]::ReadAllLines("$r\GAMMA\profiles\Test Profile\modlist.txt")
    Check ($ml[1] -eq '+Add-on - Anti-Lag for GAMMA users' -and $ml[4] -eq '+1 - Test Patch') "pack mods at top of modlist ($($ml[1..4] -join ' | '))"
    Check ($ml -contains '-Bodycam-GAMMA-Patch-2.0.1') "conflicting mod unticked"
    Check ($ml -contains '+My Own Mod' -and $ml -contains '-Disabled Mod') "own mods untouched"
    Check ((T "$r\GAMMA\profiles\Other\modlist.txt") -eq "+My Own Mod`r`n") "other profile untouched"
    Check ((T "$r\GAMMA\ModOrganizer.ini") -match '2\\title=Anomaly \(DX12 \+ Frame Gen\)') "DX12 launch entry added"
    $ltx = T "$r\Anomaly\appdata\user.ltx"
    Check ($ltx -match 'rs_v_sync off' -and $ltx -match 'mouse_sens 0\.12') "user.ltx keys set, others kept"
    Check (Test-Path -LiteralPath "$r\.slopray\shaders_cache_before_slopray\r3\x.bin") "shader cache moved aside"
    Check (Test-Path -LiteralPath "$r\UNINSTALL - Slop-Ray Engine.bat") "uninstaller in GAMMA folder"
    Check ((Rec $s).state -eq 'installed') "record state installed"
    # nothing outside what we own changed
    $rec = Rec $s
    $owned = @{}; foreach ($p in $rec.files.PSObject.Properties) { $owned[$p.Name] = $true }
    $d = @((Compare-Snap $pre (Snap $r)) | Where-Object {
        $k = $_.Substring(1)
        -not $owned.ContainsKey($k) -and $k -notlike 'Anomaly\appdata\shaders_cache\*' -and
        $k -ne 'GAMMA\profiles\Test Profile\modlist.txt' -and $k -ne 'GAMMA\ModOrganizer.ini' -and $k -ne 'Anomaly\appdata\user.ltx' })
    Check ($d.Count -eq 0) "no unrelated file changed ($($d -join ', '))"
    $script:S1 = $s; $script:S1pre = $pre
}

$scenarios['S2_existing_reshade'] = {
    $s = New-Scenario 'S2_existing_reshade'
    W "$($s.Root)\Anomaly\bin\dxgi.dll" 'reshade, not optiscaler'
    $pre = Snap $s.Root
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ((T "$($s.Root)\Anomaly\bin\dxgi.dll") -eq 'reshade, not optiscaler') "foreign dxgi.dll left alone"
    Check ($script:lastOut -match 'NOT OptiScaler') "told the user why"
    $c = Uninstall $s
    Check ($c -eq 0) "uninstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Assert-BackToOriginal $pre $s.Root "back to original"
}

$scenarios['S3_upgrade_from_old_pack'] = {
    $s = New-Scenario 'S3_upgrade_from_old_pack'
    $r = $s.Root
    $pre = Snap $r     # the real original, before the old pack
    # what a v0.5.1 install left: our old files, .old originals, old mod 3
    Copy-Item -LiteralPath "$r\Anomaly\bin\AnomalyDX11AVX.exe" "$r\Anomaly\bin\AnomalyDX11AVX.exe.old"
    W "$r\Anomaly\bin\AnomalyDX11AVX.exe" 'SR dx11 v0.5.1'
    W "$r\Anomaly\bin\AnomalyDX12.exe" 'SR dx12 v0.5.1'
    W "$r\GAMMA\mods\3 - Test Compat (0.71)\gamedata\x.ps" 'compat 0.71'
    W "$r\GAMMA\mods\3 - Test Compat (0.71)\meta.ini" 'MO2 wrote this'
    $mlp = "$r\GAMMA\profiles\Test Profile\modlist.txt"
    Copy-Item -LiteralPath $mlp "$mlp.old"
    W $mlp "# This file was automatically generated by Mod Organizer.`r`n+3 - Test Compat (0.71)`r`n+My Own Mod`r`n+410- 3DSS for GAMMA`r`n-Bodycam-GAMMA-Patch-2.0.1`r`n-Disabled Mod`r`n+Anti_Lag_for_GAMMA 1.2`r`n+190- Screen Space Shaders 23 - Ascii1457`r`n"
    $ini = "$r\GAMMA\ModOrganizer.ini"
    Copy-Item -LiteralPath $ini "$ini.old"
    $exe = "$r\Anomaly\bin\AnomalyDX12.exe" -replace '\\', '/'
    W $ini ((T $ini) -replace 'size=1', "size=2`r`n2\arguments=`r`n2\binary=$exe`r`n2\hide=false`r`n2\ownicon=true`r`n2\steamAppID=`r`n2\title=Anomaly (DX12 + Frame Gen)`r`n2\toolbar=false`r`n2\workingDirectory=x")
    $ltx = "$r\Anomaly\appdata\user.ltx"
    Copy-Item -LiteralPath $ltx "$ltx.old"
    W $ltx "r3_msaa st_opt_off`r`nrs_v_sync off`r`nmouse_sens 0.12`r`nr_upscaler dlss`r`nr_frame_generation off`r`n"
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ((T "$r\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'GAMMA original dx11') "adopted the .old as the original"
    Check (-not (Test-Path -LiteralPath "$r\Anomaly\bin\AnomalyDX11AVX.exe.old")) ".old moved into the backup"
    Check (-not (Test-Path -LiteralPath "$r\GAMMA\mods\3 - Test Compat (0.71)")) "old pack mod removed"
    Check ((Get-ChildItem -LiteralPath "$r\.slopray\recovery" -Recurse -Filter meta.ini).Count -eq 1) "unproven file of old mod kept in recovery"
    Check (-not ([IO.File]::ReadAllLines($mlp) -match 'Test Compat \(0\.71\)')) "old mod line removed"
    $c = Uninstall $s
    Check ($c -eq 2) "uninstall reports something to check (dx12 had no original) (got $c)"; Show-OnFail ($c -eq 2)
    Check ((T "$r\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'GAMMA original dx11') "real original dx11 back"
    Check ((T $mlp) -eq (T "$mlp.old")) "modlist back to the pre-Slop-Ray original"
    Check ((T $ini) -eq (T "$ini.old")) "ModOrganizer.ini back to original"
    Check ((T $ltx) -eq (T "$ltx.old")) "user.ltx back to original"
    Check ($script:lastOut -match 'older pack never saved your original') "dx12 reported as unknown original"
}

$scenarios['S4_install_twice'] = {
    $s = New-Scenario 'S4_install_twice'
    [void](Install $s)
    $a = Snap $s.Root; $ra = Rec $s
    $bk = @(Get-ChildItem -LiteralPath "$($s.Root)\.slopray\backup" -Recurse -File).Count
    # player changes a setting between runs
    W "$($s.Root)\Anomaly\appdata\user.ltx" ((T "$($s.Root)\Anomaly\appdata\user.ltx") -replace 'rs_v_sync off', 'rs_v_sync on')
    $c = Install $s
    Check ($c -eq 0) "second run exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $d = @((Compare-Snap $a (Snap $s.Root)) | Where-Object { $_ -ne '~Anomaly\appdata\user.ltx' })
    Check ($d.Count -eq 0) "second run changed nothing ($($d -join ', '))"
    Check ((T "$($s.Root)\Anomaly\appdata\user.ltx") -match 'rs_v_sync on') "player's own setting kept on re-run"
    Check (@(Get-ChildItem -LiteralPath "$($s.Root)\.slopray\backup" -Recurse -File).Count -eq $bk) "no extra backups"
    Check (@(Get-ChildItem -LiteralPath "$($s.Root)\.slopray" -Recurse -Directory -Filter 'shaders_cache*').Count -eq 1) "shader cache not moved again"
    $rb = Rec $s
    Check ($rb.files.'Anomaly\bin\AnomalyDX11AVX.exe'.baselineHash -eq $ra.files.'Anomaly\bin\AnomalyDX11AVX.exe'.baselineHash) "baseline kept"
}

$scenarios['S5_cancelled_halfway'] = {
    $s = New-Scenario 'S5_cancelled_halfway'
    $pre = Snap $s.Root
    $env:SLOPRAY_TEST_KILL_AFTER = '7'
    $c = Install $s
    Remove-Item Env:\SLOPRAY_TEST_KILL_AFTER
    Check ($c -eq 3) "process was killed (got $c)"
    Check ((Rec $s).state -eq 'installing') "record says unfinished"
    $c = Install $s
    Check ($c -eq 0) "next run undid it (got $c)"; Show-OnFail ($c -eq 0)
    Check ($script:lastOut -match 'did not finish') "told the user"
    $d = Compare-Snap $pre (Snap $s.Root)
    Check ($d.Count -eq 0) "back exactly as before ($($d -join ', '))"
    $c = Install $s
    Check ($c -eq 0 -and (Rec $s).state -eq 'installed') "then installs normally"
}

$scenarios['S6_failing_halfway'] = {
    # 3 = during the engine files, 18 = right after the modlist edit,
    # 21 = after every settings edit (while placing the uninstaller .bat)
    foreach ($n in 3, 18, 21) {
        $s = New-Scenario "S6_failing_after_$n"
        $pre = Snap $s.Root
        $env:SLOPRAY_TEST_FAIL_AFTER = "$n"
        $c = Install $s
        Remove-Item Env:\SLOPRAY_TEST_FAIL_AFTER
        Check ($c -eq 1) "failed (got $c)"; Show-OnFail ($c -eq 1)
        Check ($script:lastOut -match 'undone') "undone message"
        if ($n -ge 18) {
            $j = Get-ChildItem -LiteralPath "$($s.Root)\.slopray\runs" -Recurse -Filter journal.jsonl | Get-Content -Raw
            Check ($j -match '"op":\s*"text"') "failure came after a settings file was edited"
        }
        $d = Compare-Snap $pre (Snap $s.Root)
        Check ($d.Count -eq 0) "back exactly as before ($($d -join ', '))"
        Check (-not (Test-Path -LiteralPath "$($s.Root)\.slopray\record.json")) "no record left"
    }
}

$scenarios['S7_normal_uninstall'] = {
    $s = New-Scenario 'S7_normal_uninstall'
    $pre = Snap $s.Root
    [void](Install $s)
    $c = Uninstall $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Assert-BackToOriginal $pre $s.Root "back to original"
    Check (Test-Path -LiteralPath "$($s.Root)\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") "backup kept"
    Check (@(Get-ChildItem -LiteralPath "$($s.Root)\.slopray\logs" -Filter 'uninstall_report_*').Count -eq 1) "report written"
    # S15: second run
    $script:scenario = 'S15_uninstall_twice'
    $a = Snap $s.Root
    $c = Uninstall $s
    Check ($c -eq 0 -and $script:lastOut -match 'already uninstalled') "second uninstall: nothing to do"
    Check ((Compare-Snap $a (Snap $s.Root)).Count -eq 0) "second uninstall changed nothing"
    # clean-up after a complete uninstall
    $script:scenario = 'S7b_cleanup'
    $c = Run "$($s.Root)\.slopray\tool\cleanup_backups.ps1" $s.Root
    Check ($c -eq 0) "cleanup exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check (-not (Get-ChildItem -LiteralPath "$($s.Root)\.slopray\backup" -Recurse -File -ErrorAction SilentlyContinue)) "backups removed"
    Assert-BackToOriginal $pre $s.Root "cleanup changed no game file"
    # reinstall after a full uninstall + cleanup still works and backs up again
    $script:scenario = 'S7c_reinstall'
    $c = Install $s
    Check ($c -eq 0) "reinstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ((T "$($s.Root)\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'GAMMA original dx11') "original backed up again"
}

$scenarios['S8_user_modified'] = {
    $s = New-Scenario 'S8_user_modified'
    $r = $s.Root
    $pre = Snap $r
    [void](Install $s)
    W "$r\Anomaly\bin\AnomalyDX11AVX.exe" 'player patched our dx11'        # replaced file, changed: case B
    W "$r\Anomaly\bin\AnomalyDX12.exe" 'player patched our dx12'           # added file, changed: case D
    W "$r\GAMMA\mods\1 - Test Patch\gamedata\configs\a.ltx" 'player tweak' # added file, changed: case D
    W "$r\Anomaly\appdata\user.ltx" ((T "$r\Anomaly\appdata\user.ltx") -replace 'r_upscaler fsr3|r_upscaler dlss', 'r_upscaler xess')
    $c = Uninstall $s
    Check ($c -eq 2) "exit 2 = needs attention (got $c)"; Show-OnFail ($c -eq 2)
    Check ((T "$r\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'player patched our dx11') "B: changed file kept"
    Check (-not (Test-Path -LiteralPath "$r\Anomaly\bin\AnomalyDX12.exe")) "D: moved out of bin"
    Check ((Get-ChildItem -LiteralPath "$r\.slopray\recovery" -Recurse -File | Where-Object { (T $_.FullName) -eq 'player patched our dx12' }).Count -eq 1) "D: dx12 in recovery"
    Check ((Get-ChildItem -LiteralPath "$r\.slopray\recovery" -Recurse -File | Where-Object { (T $_.FullName) -eq 'player tweak' }).Count -eq 1) "D: mod tweak in recovery"
    Check ((T "$r\Anomaly\appdata\user.ltx") -match 'r_upscaler xess' -and (T "$r\Anomaly\appdata\user.ltx") -match 'rs_v_sync on') "own setting kept, ours put back"
    Check ((T "$r\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'GAMMA original dx11') "original still in backup"
    $c = Run "$r\.slopray\tool\cleanup_backups.ps1" $r
    Check ($c -eq 1 -and (Test-Path -LiteralPath "$r\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe")) "cleanup refuses after a partial uninstall"
}

$scenarios['S9_missing_backup'] = {
    $s = New-Scenario 'S9_missing_backup'
    [void](Install $s)
    [IO.File]::Delete("$($s.Root)\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe")
    $c = Uninstall $s
    Check ($c -eq 2) "exit 2 (got $c)"; Show-OnFail ($c -eq 2)
    Check ((T "$($s.Root)\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'SR dx11 v0.5.2') "E: current file left in place"
    Check ($script:lastOut -match 'backup missing or damaged') "E: reported"
    Check ((T "$($s.Root)\Anomaly\db\mods\00_modded_exes_gamedata.db0") -eq 'GAMMA original db0') "the rest still restored"
}

$scenarios['S10_corrupt_backup'] = {
    $s = New-Scenario 'S10_corrupt_backup'
    [void](Install $s)
    W "$($s.Root)\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe" 'garbage'
    $c = Uninstall $s
    Check ($c -eq 2) "exit 2 (got $c)"; Show-OnFail ($c -eq 2)
    Check ((T "$($s.Root)\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'SR dx11 v0.5.2') "E: current file not overwritten with garbage"
    Check ((T "$($s.Root)\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'garbage') "E: damaged backup not deleted"
}

$scenarios['S11_modlist_changed'] = {
    $s = New-Scenario 'S11_modlist_changed'
    $r = $s.Root
    [void](Install $s)
    $mlp = "$r\GAMMA\profiles\Test Profile\modlist.txt"
    $ml = [IO.File]::ReadAllLines($mlp)
    # player: re-orders own mods, adds a new mod, unticks one of ours
    $new = @($ml[0], '+New Mod') + ($ml[1..($ml.Count - 1)] | ForEach-Object { if ($_ -eq '+1 - Test Patch') { '-1 - Test Patch' } else { $_ } })
    $i = [array]::IndexOf($new, '+My Own Mod'); $j = [array]::IndexOf($new, '+410- 3DSS for GAMMA')
    $new[$i] = '+410- 3DSS for GAMMA'; $new[$j] = '+My Own Mod'
    W $mlp (($new -join "`r`n") + "`r`n")
    $c = Uninstall $s
    $after = [IO.File]::ReadAllLines($mlp)
    Check ($after -contains '+New Mod') "new mod line kept"
    Check ([array]::IndexOf($after, '+410- 3DSS for GAMMA') -lt [array]::IndexOf($after, '+My Own Mod')) "player's order kept"
    Check ($after -contains '+Bodycam-GAMMA-Patch-2.0.1') "mod we unticked is ticked again"
    Check (-not ($after -match 'Anti-Lag for GAMMA users|Test Compat|stock Atmospherics')) "our lines removed"
    Check ($after -contains '-1 - Test Patch' -or -not ($after -match '1 - Test Patch')) "line the player changed is not forced"
    Check ((T "$r\GAMMA\profiles\Other\modlist.txt") -eq "+My Own Mod`r`n") "other profile untouched"
}

$scenarios['S12_3dss'] = {
    $s = New-Scenario 'S12_3dss_custom_files'
    $f = "$($s.Root)\GAMMA\mods\410- 3DSS for GAMMA\gamedata\configs\my_custom.ltx"
    $h = Sha $f
    [void](Install $s); [void](Uninstall $s)
    Check ((Sha $f) -eq $h) "custom 3DSS file untouched through install + uninstall"
    $script:scenario = 'S12b_legacy_3dss_backup'
    $s = New-Scenario 'S12b_legacy_3dss_backup'
    $m = "$($s.Root)\GAMMA\mods\410- 3DSS for GAMMA"
    W "$m\gamedata\scripts\z_3dss_lens_hider.script" '5.02 merge'
    W "$($s.Root)\GAMMA\3DSS_backup\410- 3DSS for GAMMA\gamedata\scripts\lewd_lens_hider.script" '4.17'
    W "$($s.Root)\GAMMA\3DSS_backup\410- 3DSS for GAMMA\gamedata\configs\mod_system_3dss_dummy_scopes.ltx" '3dss 4.17'
    [void](Install $s)
    Check ($null -ne (Rec $s).legacy3dss) "legacy 3DSS backup recorded"
    $c = Uninstall $s
    Check ($c -eq 0) "uninstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ((Test-Path -LiteralPath "$m\gamedata\scripts\lewd_lens_hider.script") -and -not (Test-Path -LiteralPath "$m\gamedata\scripts\z_3dss_lens_hider.script")) "GAMMA's own 410 is back"
    Check (@(Get-ChildItem -LiteralPath "$($s.Root)\.slopray\recovery" -Recurse -Filter 'z_3dss_lens_hider.script').Count -eq 1) "5.02 merge kept in recovery"
    Check (-not (Test-Path -LiteralPath "$($s.Root)\GAMMA\3DSS_backup")) "empty 3DSS_backup removed"
}

$scenarios['S14_uninstall_interrupted'] = {
    $s = New-Scenario 'S14_uninstall_interrupted'
    $pre = Snap $s.Root
    [void](Install $s)
    $env:SLOPRAY_TEST_KILL_AFTER = '4'
    $c = Uninstall $s
    Remove-Item Env:\SLOPRAY_TEST_KILL_AFTER
    Check ($c -eq 3) "killed (got $c)"
    Check ((Rec $s).state -eq 'uninstalling') "record says unfinished"
    $c = Uninstall $s
    Check ($c -eq 0) "second run finishes (got $c)"; Show-OnFail ($c -eq 0)
    Assert-BackToOriginal $pre $s.Root "back to original"
}

$scenarios['S16_zip_slip_and_junction'] = {
    $s = New-Scenario 'S16_zip_escape'
    $pre = Snap $s.Root
    # a mod zip with an entry that climbs out of the mod folder
    $z = "$($s.Pack)\STEP 2 - MO2 mods\2 - Evil.zip"
    $fs = [IO.File]::Create($z); $a = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    $w = New-Object IO.StreamWriter($a.CreateEntry('gamedata/ok.txt').Open()); $w.Write('ok'); $w.Close()
    $w = New-Object IO.StreamWriter($a.CreateEntry('../../../../evil.txt').Open()); $w.Write('evil'); $w.Close()
    $a.Dispose(); $fs.Close()
    $c = Install $s
    Check ($c -eq 1) "install refused (got $c)"; Show-OnFail ($c -eq 1)
    Check (-not (Get-ChildItem -LiteralPath $base -Recurse -Filter evil.txt -ErrorAction SilentlyContinue)) "nothing written outside"
    Check ((Compare-Snap $pre (Snap $s.Root)).Count -eq 0) "undone"
    $s = New-Scenario 'S16b_junction'
    $outside = "$base\outside_target"
    [void][IO.Directory]::CreateDirectory($outside)
    cmd /c mklink /J "$($s.Root)\Anomaly\bin\streamline" "$outside" | Out-Null
    $pre = Snap $s.Root
    $c = Install $s
    Check ($c -eq 1) "install refused through a junction (got $c)"; Show-OnFail ($c -eq 1)
    Check (-not (Get-ChildItem -LiteralPath $outside -Force)) "nothing written through the junction"
    Check ((Compare-Snap $pre (Snap $s.Root)).Count -eq 0) "undone"
}

# MSAA is not a preference: the upscaler and the night vision shaders break with it, so
# every run puts it back off, while the player's other settings are still kept.
$scenarios['S18_msaa_forced_off_every_run'] = {
    $s = New-Scenario 'S18_msaa_forced_off_every_run'
    $ltxp = "$($s.Root)\Anomaly\appdata\user.ltx"
    $orig = T $ltxp
    [void](Install $s)
    Check ((T $ltxp) -match '(?m)^r3_msaa st_opt_off\s*$') "first install sets MSAA off"
    # the player (or a settings change) turns MSAA on again, and changes vsync
    W $ltxp (((T $ltxp) -replace 'r3_msaa st_opt_off', 'r3_msaa 8x') -replace 'rs_v_sync off', 'rs_v_sync on')
    $c = Install $s
    Check ($c -eq 0) "second run exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $t = T $ltxp
    Check ($t -match '(?m)^r3_msaa st_opt_off\s*$') "re-run puts MSAA back off"
    Check ($t -notmatch 'r3_msaa 8x') "no 8x left"
    Check ($t -match 'rs_v_sync on' -and $t -match 'mouse_sens 0\.12') "other settings kept"
    Check ($script:lastOut -match 'r3_msaa st_opt_off') "the run says it set MSAA"
    [void](Uninstall $s)
    Check ((T $ltxp) -eq $orig) "uninstall restores the original MSAA line and user.ltx"
}

# GAMMA directly on a drive ("C:\Anomaly" + "C:\GAMMA"): the root is trimmed to "C:",
# which .NET reads as "the current directory on drive C". Reproduced with a SUBST
# drive whose root is the fake game, started from a folder on that same drive (a pack
# unzipped on the game's drive, as a double-click does).
$scenarios['S30_reverted_dlss5_then_plain'] = {
    # B3 (misterfister): "3 installed file(s) did not verify" (dxgi.dll, OptiScaler.ini,
    # nvngx_dlssnr.dll) on a re-run after reverting by hand. The earlier run had DLSS 5;
    # the re-run does not place those files at all, so they must not be checked.
    $s = New-Scenario 'S30_reverted_dlss5_then_plain'
    $c = Install $s @('-Dlss5')
    Check ($c -eq 0) "DLSS 5 install exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    foreach ($f in 'dxgi.dll', 'OptiScaler.ini', 'nvngx_dlssnr.dll') { [IO.File]::Delete("$($s.Root)\Anomaly\bin\$f") }
    $c = Run "$($s.Pack)\install.ps1" $s.Root @('-GpuName', 'NVIDIA GeForce RTX 5080')
    Check ($c -eq 0) "plain re-run on a GPU without OptiScaler exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ($script:lastOut -notmatch 'did not verify') "no verify failure for files this run did not place"
    $c = Install $s
    Check ($c -eq 0) "plain re-run on RTX 3060 (OptiScaler, no DLSS 5) exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ((T "$($s.Root)\Anomaly\bin\dxgi.dll") -eq 'optiscaler dll') "OptiScaler placed again"
    $c = Uninstall $s
    Check ($c -eq 0 -or $c -eq 2) "uninstall runs (got $c)"; Show-OnFail ($c -eq 0 -or $c -eq 2)
    Check (-not (Test-Path -LiteralPath "$($s.Root)\Anomaly\bin\dxgi.dll")) "OptiScaler removed by uninstall"
}

$scenarios['S31_split_layout'] = {
    # B2 (jefferysteele): Anomaly in one place, the MO2 folder somewhere else; MO2's gamePath links them
    $s = New-Scenario 'S31_split_layout'
    $d = Split-Path -Parent $s.Root
    $an = "$d\Anomaly Game (" + [char]0xFC + ")"
    $mo = "$d\MO2 & stuff\GAMMA RC3"
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $mo))
    [IO.Directory]::Move("$($s.Root)\Anomaly", $an)
    [IO.Directory]::Move("$($s.Root)\GAMMA", $mo)
    [IO.Directory]::Delete($s.Root)
    W "$mo\ModOrganizer.ini" ((T "$mo\ModOrganizer.ini") -replace '\[General\]\r\n', "[General]`r`ngamePath=$(ConvertTo-QtValue $an)`r`n")
    $pre = Snap $d
    # the Anomaly folder alone: no MO2 folder next to it, so say what is missing
    $c = Run "$($s.Pack)\install.ps1" $an $gpu
    Check ($c -eq 1 -and $script:lastOut -match 'no G\.A\.M\.M\.A\. MO2 folder') "Anomaly folder alone: clear message (got $c)"; Show-OnFail ($c -eq 1)
    Check ((Compare-Snap $pre (Snap $d)).Count -eq 0) "nothing changed by the refused run"
    # the MO2 folder: its gamePath leads to Anomaly
    $c = Run "$($s.Pack)\install.ps1" $mo $gpu
    Check ($c -eq 0) "install from the MO2 folder exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ((T "$an\bin\AnomalyDX11AVX.exe") -eq 'SR dx11 v0.5.2') "engine placed in the Anomaly folder"
    Check (Test-Path -LiteralPath "$mo\mods\1 - Test Patch\gamedata\configs\a.ltx") "pack mod placed in the MO2 folder"
    Check ((T "$an\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'GAMMA original dx11') "original in the backup (logical path)"
    Check ((T "$mo\profiles\Test Profile\modlist.txt") -match '\+1 - Test Patch') "modlist ticked"
    $rec = Get-Content -LiteralPath "$an\.slopray\record.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Check ($rec.mo2 -eq $mo -and $rec.anomaly -eq $an) "record names both folders"
    # once installed, the Anomaly folder alone is enough (the record knows the MO2 folder)
    $c = Run "$($s.Pack)\install.ps1" $an $gpu
    Check ($c -eq 0) "re-run from the Anomaly folder exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $c = Run "$an\.slopray\tool\uninstall.ps1" $an
    Check ($c -eq 0) "uninstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    # .slopray (backups, logs) stays; in this layout it lives in the Anomaly folder
    $diff = @((Compare-Snap $pre (Snap $d)) | Where-Object { $_ -notmatch 'shaders_cache|UNINSTALL - Slop-Ray|CLEAN UP BACKUPS|\\\.slopray\\' })
    Check ($diff.Count -eq 0) "both folders back to the original ($($diff -join ', '))"
}

$scenarios['S32_two_installs'] = {
    # B1 (RevRole): two GAMMA installs; never pick one silently
    $s = New-Scenario 'S32_two_installs'
    $second = "$(Split-Path -Parent $s.Root)\Second GAMMA"
    New-Gamma $second
    $env:SLOPRAY_TEST_SEARCH_ONLY = "$($s.Root);$second"
    $c = RunFind "$($s.Pack)\install.ps1" $gpu
    Check ($c -eq 1 -and $script:lastOut -match 'more than one' -and $script:lastOut -match [regex]::Escape($second)) "two found: listed and refused under -Yes (got $c)"; Show-OnFail ($c -eq 1)
    Check (-not (Test-Path -LiteralPath "$($s.Root)\.slopray") -and -not (Test-Path -LiteralPath "$second\.slopray")) "neither touched"
    $env:SLOPRAY_TEST_SEARCH_ONLY = "$second"
    $c = RunFind "$($s.Pack)\install.ps1" $gpu
    Check ($c -eq 0 -and (Test-Path -LiteralPath "$second\.slopray\record.json")) "one found: used without asking (got $c)"; Show-OnFail ($c -eq 0)
    Remove-Item Env:\SLOPRAY_TEST_SEARCH_ONLY
}

$scenarios['S33_no_gamma'] = {
    # B4 (jefferysteele): Anomaly but no G.A.M.M.A. MO2 folder: one clear message, before anything else
    $s = New-Scenario 'S33_no_gamma'
    Remove-Item -LiteralPath "$($s.Root)\GAMMA" -Recurse -Force      # test fixture only
    $c = Run "$($s.Pack)\install.ps1" $s.Root $gpu
    Check ($c -eq 1 -and $script:lastOut -match 'Install G\.A\.M\.M\.A\. first') "-GamePath: says install G.A.M.M.A. first (got $c)"; Show-OnFail ($c -eq 1)
    Check ($script:lastOut -notmatch 'MO2 profile|3DSS') "stops before the later steps"
    $env:SLOPRAY_TEST_SEARCH_ONLY = "$($s.Root)"
    $c = RunFind "$($s.Pack)\install.ps1" $gpu
    Check ($c -eq 1 -and $script:lastOut -match 'no G\.A\.M\.M\.A\. install found') "search: says none found (got $c)"; Show-OnFail ($c -eq 1)
    Remove-Item Env:\SLOPRAY_TEST_SEARCH_ONLY
    Check (-not (Test-Path -LiteralPath "$($s.Root)\.slopray")) "nothing written"
}

$scenarios['S34_model_drop_duplicate'] = {
    # B5 (Bisanch): DLTX duplicate between items_model_drop_physc_mre.ltx and _newfddaanim.ltx
    $s = New-Scenario 'S34_model_drop_duplicate'
    $r = $s.Root
    $kute = '453- Items Model Drop After Usage - Kute'
    W "$r\GAMMA\mods\Model Drop 15\gamedata\configs\items\items\items_model_drop_physc_mre.ltx" '[x]'
    W "$r\GAMMA\mods\$kute\gamedata\configs\items\items\items_model_drop_physc_newfddaanim.ltx" '[x]'
    W "$r\GAMMA\mods\xx-Drinks Compendium\gamedata\configs\items\items\items_model_drop_physc_montter_green.ltx" '[y]'
    foreach ($m in 'Model Drop 15', $kute, 'xx-Drinks Compendium') { Add-ModLine $s "+$m" }
    $c = Install $s
    Check ($c -eq 0) "install exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $ml = ML $s
    Check ($ml -contains "-$kute") "453 unticked"
    Check ($ml -contains '+Model Drop 15' -and $ml -contains '+xx-Drinks Compendium') "Model Drop 15 and the 453 add-on stay ticked"
    [void](Uninstall $s)
    Check ((ML $s) -contains "+$kute") "uninstall ticks 453 again"
    # the same pair from two other mods: warn, change nothing
    $s = New-Scenario 'S34b_model_drop_other_mods'
    W "$($s.Root)\GAMMA\mods\Model Drop 15\gamedata\configs\items\items\items_model_drop_physc_mre.ltx" '[x]'
    W "$($s.Root)\GAMMA\mods\FDDA Something\gamedata\configs\items\items\items_model_drop_physc_newfddaanim.ltx" '[x]'
    foreach ($m in 'Model Drop 15', 'FDDA Something') { Add-ModLine $s "+$m" }
    $c = Install $s
    Check ($c -eq 0 -and $script:lastOut -match "both define the Model Drop sections") "warned (got $c)"; Show-OnFail ($c -eq 0)
    Check ((ML $s) -contains '+FDDA Something' -and (ML $s) -contains '+Model Drop 15') "nothing unticked"
}

$scenarios['S35_preflight_warnings'] = {
    # B6 (Mister Lighto, stubkan, QRsavage): warn about old PiP mods, other NVG mods and loose
    # shader files; never untick or delete them. Beef's + Better Beef's together is normal.
    $s = New-Scenario 'S35_preflight_warnings'
    $r = $s.Root
    W "$r\GAMMA\mods\Old PiP Mod\gamedata\shaders\r3\svp_hooks_inside.h" 'old pip'
    W "$r\GAMMA\mods\Real_NVGs_TEST\gamedata\shaders\r3\nightvision_gen_1.ps" 'real nvg'
    W "$r\GAMMA\mods\189- Beef's NVG - theRealBeef\gamedata\shaders\r3\nightvision_gen_1.ps" 'beef'
    W "$r\GAMMA\mods\410- 3DSS for GAMMA\gamedata\shaders\r3\scope_common.h" '3dss scope'
    W "$r\Anomaly\gamedata\shaders\r3\scope_old.ps" 'loose'
    foreach ($m in 'Old PiP Mod', 'Real_NVGs_TEST', "189- Beef's NVG - theRealBeef") { Add-ModLine $s "+$m" }
    $pre = Snap $r
    $c = Install $s
    Check ($c -eq 0) "install exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $o = $script:lastOut
    Check ($o -match "'Old PiP Mod' ships old bodycam/PiP shaders") "warns about the old PiP mod"
    Check ($o -match "'Real_NVGs_TEST' replaces the night vision") "warns about the other NVG mod"
    Check ($o -notmatch "'189- Beef's NVG - theRealBeef' replaces") "no warning for Beef's NVG"
    Check ($o -notmatch "'410- 3DSS for GAMMA' ships") "no warning for 3DSS's own scope shaders"
    Check ($o -match '1 loose shader file\(s\) in Anomaly') "warns about the loose file"
    $ml = ML $s
    Check ($ml -contains '+Old PiP Mod' -and $ml -contains '+Real_NVGs_TEST') "warned mods stay ticked"
    Check ((T "$r\Anomaly\gamedata\shaders\r3\scope_old.ps") -eq 'loose') "loose file left where it is"
}

$scenarios['S36_optiscaler_version'] = {
    # OptiScaler F5 0.1.35 (default, in STEP 6) or 0.1.38 (overlay "STEP 6\F5 0.1.38"), per .bat
    $s = New-Scenario 'S36_optiscaler_version'
    $bin = "$($s.Root)\Anomaly\bin"
    $c = Install $s
    Check ($c -eq 0 -and (T "$bin\dxgi.dll") -eq 'optiscaler dll') "default = 0.1.35 (got $c)"; Show-OnFail ($c -eq 0)
    Check (-not (Test-Path -LiteralPath "$bin\F5 0.1.38")) "the version folder itself is not copied into bin"
    $c = Install $s @('-OptiScaler', '0.1.38')
    Check ($c -eq 0 -and (T "$bin\dxgi.dll") -eq 'optiscaler 0138') "re-run with 0.1.38 swaps dxgi.dll (got $c)"; Show-OnFail ($c -eq 0)
    Check ((T "$bin\OptiScaler.ini") -match 'FGOutput=auto') "0.1.38's own ini placed"
    Check ((T "$bin\OptiScaler\libxess.dll") -eq 'xess') "files 0.1.38 does not change stay the shared ones"
    Check ($script:lastOut -match 'OptiScaler F5 0\.1\.38') "the run says which version"
    $c = Install $s @('-Dlss5', '-OptiScaler', '0.1.38')
    $ini = T "$bin\OptiScaler.ini"
    Check ($c -eq 0 -and $ini -match 'FGOutput=auto' -and $ini -match '(?m)^Enabled=true') "DLSS 5 on 0.1.38: its ini with DLSS 5 switched on (got $c)"; Show-OnFail ($c -eq 0)
    Check (Test-Path -LiteralPath "$bin\nvngx_dlssnr.dll") "DLSS 5 model placed"
    $c = Install $s
    Check ($c -eq 0 -and (T "$bin\dxgi.dll") -eq 'optiscaler dll') "back to 0.1.35 (got $c)"; Show-OnFail ($c -eq 0)
    Check (-not (Get-ChildItem -LiteralPath "$($s.Root)\.slopray\recovery" -Recurse -Filter 'dxgi.dll' -ErrorAction SilentlyContinue)) "swapping never treats our own dxgi.dll as yours"
    $c = Uninstall $s
    Check (-not (Test-Path -LiteralPath "$bin\dxgi.dll")) "uninstall removes OptiScaler (got $c)"
    # a pack without the 0.1.38 folder: stop before changing anything
    $s = New-Scenario 'S36b_optiscaler_version_missing'
    Remove-Item -LiteralPath "$($s.Pack)\STEP 6 - OptiScaler\F5 0.1.38" -Recurse -Force      # test fixture only
    $c = Install $s @('-OptiScaler', '0.1.38')
    Check ($c -eq 1 -and $script:lastOut -match 'OptiScaler 0\.1\.38 is not in this pack') "missing version: clear stop (got $c)"; Show-OnFail ($c -eq 1)
    Check (-not (Test-Path -LiteralPath "$($s.Root)\.slopray")) "nothing written"
}

$scenarios['S17_game_on_drive_root'] = {
    $s = New-Scenario 'S17_game_on_drive_root'
    $used = [IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpper() }
    $letter = ([char[]](90..68) | Where-Object { "$_" -notin $used } | Select-Object -First 1)
    if (-not $letter) { Write-Host "    SKIP: no free drive letter for subst"; return }
    $drv = "${letter}:"
    $real = $s.Root
    Copy-Item -LiteralPath $s.Pack -Destination "$real\_pack" -Recurse
    cmd /c subst $drv "$real" | Out-Null
    try {
        $pre = Snap $real
        $log = "$base\S17_out.txt"
        $args17 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$drv\_pack\install.ps1`"",
                    '-Yes', '-GpuName', "`"NVIDIA GeForce RTX 3060`"")      # no -GamePath: found from the pack's parent, as for a player
        # the same drive typed or passed as -GamePath ("C:\" at the prompt)
        $p = Start-Process powershell.exe -WorkingDirectory "$drv\_pack" -Wait -PassThru -NoNewWindow `
             -RedirectStandardOutput $log -ArgumentList ($args17 + @('-GamePath', $drv, '-DryRun'))
        $script:lastOut = Get-Content -LiteralPath $log -Raw
        Check ($p.ExitCode -eq 0) "-GamePath on a drive root dry run exit 0 (got $($p.ExitCode))"; Show-OnFail ($p.ExitCode -eq 0)
        # a real drive root lets a normal user create folders but not files (C:\ does)
        $who = "$env:USERDOMAIN\$env:USERNAME"
        icacls "$real" /deny "${who}:(WD)" | Out-Null
        $p = Start-Process powershell.exe -ArgumentList $args17 -WorkingDirectory "$drv\_pack" -Wait -PassThru `
             -NoNewWindow -RedirectStandardOutput $log
        $script:lastOut = Get-Content -LiteralPath $log -Raw
        Check ($p.ExitCode -eq 0) "install on a drive root exit 0 (got $($p.ExitCode))"; Show-OnFail ($p.ExitCode -eq 0)
        Check (Test-Path -LiteralPath "$real\.slopray\tool\UNINSTALL - Slop-Ray Engine.bat") "the uninstaller bat is in .slopray\tool"
        Check (Test-Path -LiteralPath "$real\.slopray\record.json") "record lives in the game folder"
        Check (-not (Test-Path -LiteralPath "$real\_pack\.slopray")) "nothing written into the pack folder"
        Check ((T "$real\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'SR dx11 v0.5.2') "dx11 exe installed in the game folder"
        Check ((T "$real\.slopray\backup\Anomaly\bin\AnomalyDX11AVX.exe") -eq 'GAMMA original dx11') "original saved"
        $p = Start-Process powershell.exe -WorkingDirectory "$drv\_pack" -Wait -PassThru -NoNewWindow `
             -RedirectStandardOutput $log -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
             "`"$drv\.slopray\tool\uninstall.ps1`"", '-Yes')
        $script:lastOut = Get-Content -LiteralPath $log -Raw
        Check ($p.ExitCode -eq 0) "uninstall on a drive root exit 0 (got $($p.ExitCode))"; Show-OnFail ($p.ExitCode -eq 0)
        Assert-BackToOriginal $pre $real "uninstall on a drive root restores everything"
    } finally {
        if ($who) { icacls "$real" /remove:d "$who" | Out-Null }
        cmd /c subst $drv /d | Out-Null
    }
}

# --- SSS revert (tests\SSS_REVERT_TEST_PLAN.md) --------------------------------
$scenarios['S19_sss24_install'] = {
    $s = New-Scenario 'S19_sss24_install'
    New-Sss24Setup $s
    $r = $s.Root
    $pre = Snap $r
    $otherBefore = T "$r\GAMMA\profiles\Other\modlist.txt"
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $ml = ML $s
    Check ($ml -contains "-$sss24") "SSS24 mod unticked"
    Check ($ml -contains "-$mt") "MT-TEST db0 mod unticked"
    Check ($ml -contains "+$sss23") "SSS 23 ticked"
    Check ($ml -contains '+My Own Mod' -and $ml -contains '-Disabled Mod') "own mods untouched"
    Check ([array]::IndexOf($ml, '+My Own Mod') -lt [array]::IndexOf($ml, "-$mt") -and
           [array]::IndexOf($ml, "-$mt") -lt [array]::IndexOf($ml, "-$sss24") -and
           [array]::IndexOf($ml, "-$sss24") -lt [array]::IndexOf($ml, "+$sss23")) "player's order kept"
    Check ((T "$r\GAMMA\profiles\Other\modlist.txt") -eq $otherBefore) "other profile untouched"
    foreach ($d in $sl) {
        Check (-not (Test-Path -LiteralPath "$r\Anomaly\bin\$d")) "$d out of bin"
        Check ((T "$r\.slopray\backup\Anomaly\bin\$d") -eq "sss24 sl 2.11.1 $d") "$d in backup"
    }
    Check ((T "$r\Anomaly\bin\streamline\sl.common.dll") -eq 'sl common') "STEP 7 streamline installed"
    Check ((T "$r\Anomaly\gamedata\shaders\r3\combine_2_naa.ps") -eq 'gamma combine') "missing GAMMA shader restored"
    Check ((T "$r\Anomaly\gamedata\scripts\gamma_patch.script") -eq 'gamma script') "missing GAMMA script restored"
    Check ((T "$r\Anomaly\gamedata\configs\x.ltx") -eq 'player config') "existing gamedata file not overwritten"
    Check (-not (Test-Path -LiteralPath "$r\Anomaly\bin\AnomalyDX11.exe")) "modpack_patches\bin not copied"
    $rec = Rec $s
    Check ($rec.files.'Anomaly\gamedata\scripts\gamma_patch.script'.baseline -eq 'absent') "restored file recorded as Introduced"
    Check ($rec.files.'Anomaly\bin\sl.interposer.dll'.installedHash -eq 'absent') "DLL move recorded"
    $mr = $rec.modlist.$mlRel
    Check ($mr.$sss24.baseline -eq '+' -and $mr.$mt.baseline -eq '+' -and $mr.$sss23.baseline -eq '-') "modlist baselines are the SSS24 values"
    Check ($script:lastOut -match 'SSS24 found' -and $script:lastOut -match [regex]::Escape($sss24) -and
           $script:lastOut -match [regex]::Escape($mt) -and $script:lastOut -match 'uninstall brings SSS24 back') "summary block"
    $owned = @{}; foreach ($p in $rec.files.PSObject.Properties) { $owned[$p.Name] = $true }
    $d = @((Compare-Snap $pre (Snap $r)) | Where-Object {
        $k = $_.Substring(1)
        -not $owned.ContainsKey($k) -and $k -notlike 'Anomaly\appdata\shaders_cache\*' -and
        $k -ne $mlRel -and $k -ne 'GAMMA\ModOrganizer.ini' -and $k -ne 'Anomaly\appdata\user.ltx' })
    Check ($d.Count -eq 0) "no unrelated file changed ($($d -join ', '))"
    $script:scenario = 'S19b_sss24_uninstall'
    $c = Uninstall $s
    Check ($c -eq 0) "uninstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Assert-BackToOriginal $pre $r "SSS24 setup back"
}

$scenarios['S20_sss24_dry_run'] = {
    $s = New-Scenario 'S20_sss24_dry_run'
    New-Sss24Setup $s
    $pre = Snap $s.Root
    $c = Install $s @('-DryRun')
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ((Compare-Snap $pre (Snap $s.Root)).Count -eq 0) "changed nothing"
    Check (-not (Test-Path -LiteralPath "$($s.Root)\.slopray")) "no .slopray folder"
    Check ($script:lastOut -match [regex]::Escape($sss24) -and $script:lastOut -match [regex]::Escape($mt) -and
           $script:lastOut -match [regex]::Escape($sss23)) "names the mods"
    Check ($script:lastOut -match 'restore 2 GAMMA patch files' -and $script:lastOut -match 'move 5 loose Streamline DLLs') "names the file counts"
}

# the SSS revert must not start at all: exit 1, nothing changed
function Assert-Refused ($s, $pattern, $what) {
    $pre = Snap $s.Root
    $c = Install $s
    Check ($c -eq 1) "$what : exit 1 (got $c)"; Show-OnFail ($c -eq 1)
    Check ((Compare-Snap $pre (Snap $s.Root)).Count -eq 0) "$what : nothing changed"
    Check (-not (Test-Path -LiteralPath "$($s.Root)\.slopray")) "$what : no .slopray folder"
    Check ($script:lastOut -match $pattern) "$what : says why"
}

$scenarios['S21_sss23_missing'] = {
    $s = New-Scenario 'S21_sss23_missing'
    New-Sss24Setup $s -NoSss23
    Assert-Refused $s ([regex]::Escape($sss23)) 'SSS 23 missing'
    $script:scenario = 'S21b_sss23_not_23_5'
    $s = New-Scenario 'S21b_sss23_not_23_5'
    New-Sss24Setup $s -OldSss23
    Assert-Refused $s 'not 23\.5' 'SSS 23 too old'
}

$scenarios['S22_other_sss24_mod'] = {
    $s = New-Scenario 'S22_other_sss24_mod'
    New-Sss24Setup $s
    W "$($s.Root)\GAMMA\mods\Atmos SSS24 variant\gamedata\shaders\r3\screenspace_materials.h" 'atmos sss24'
    Add-ModLine $s '+Atmos SSS24 variant'
    Assert-Refused $s 'Atmos SSS24 variant' 'other SSS24 shader mod'
    $script:scenario = 'S22b_unticked_other_sss24_mod'
    $s = New-Scenario 'S22b_unticked_other_sss24_mod'
    New-Sss24Setup $s
    W "$($s.Root)\GAMMA\mods\Atmos SSS24 variant\gamedata\shaders\r3\screenspace_materials.h" 'atmos sss24'
    Add-ModLine $s '-Atmos SSS24 variant'
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $ml = ML $s
    Check ($ml -contains "-$sss24" -and $ml -contains "+$sss23") "revert ran"
    Check ($ml -contains '-Atmos SSS24 variant') "unticked mod left as is"
}

$scenarios['S23_patch_source_missing'] = {
    $s = New-Scenario 'S23_patch_source_missing'
    New-Sss24Setup $s -NoPatches
    Assert-Refused $s 'modpack_patches' 'GAMMA patch source missing'
}

$scenarios['S24_plain_gamma_no_revert'] = {
    $s = New-Scenario 'S24_plain_gamma_no_revert'
    $r = $s.Root
    W "$r\$patches\gamedata\scripts\gamma_patch.script" 'gamma script'
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ($script:lastOut -notmatch 'SSS24') "no SSS revert block"
    Check (-not (Test-Path -LiteralPath "$r\Anomaly\gamedata")) "no GAMMA patch file copied"
    $ml = ML $s
    Check ($ml[1] -eq '+Add-on - Anti-Lag for GAMMA users' -and $ml[4] -eq '+1 - Test Patch' -and
           $ml -contains '-Bodycam-GAMMA-Patch-2.0.1' -and $ml -contains '+My Own Mod') "modlist as in S1"
}

$scenarios['S25_foreign_db0_mod'] = {
    $s = New-Scenario 'S25_foreign_db0_mod'
    $r = $s.Root
    W "$r\GAMMA\mods\Old modded exes\db\mods\00_modded_exes_gamedata.db0" 'old db0'
    W "$r\GAMMA\mods\Repack of ours\db\mods\00_modded_exes_gamedata.db0" 'SR db0 v0.5.2'
    Add-ModLine $s '+Old modded exes'
    Add-ModLine $s '+Repack of ours'
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $ml = ML $s
    Check ($ml -contains '-Old modded exes') "foreign db0 mod unticked"
    Check ($ml -contains '+Repack of ours') "mod with our own db0 kept"
    Check ($script:lastOut -notmatch 'SSS24') "no SSS revert without SSS24"
    [void](Uninstall $s)
    Check ((ML $s) -contains '+Old modded exes') "uninstall ticks it again"
}

$scenarios['S26_sss24_install_twice'] = {
    $s = New-Scenario 'S26_sss24_install_twice'
    New-Sss24Setup $s
    $pre = Snap $s.Root
    [void](Install $s)
    $c = Install $s
    Check ($c -eq 0) "second run exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ($script:lastOut -notmatch 'SSS24 found') "nothing left to revert"
    Check ((Rec $s).modlist.$mlRel.$sss24.baseline -eq '+') "baseline still the SSS24 value"
    $c = Uninstall $s
    Check ($c -eq 0) "uninstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Assert-BackToOriginal $pre $s.Root "SSS24 setup back after two installs"
}

$scenarios['S27_player_reticks_sss24'] = {
    $s = New-Scenario 'S27_player_reticks_sss24'
    New-Sss24Setup $s
    $r = $s.Root
    [void](Install $s)
    W "$r\$mlRel" ((((ML $s) -join "`r`n") -replace [regex]::Escape("-$sss24"), "+$sss24") + "`r`n")
    $c = Uninstall $s
    Check ($c -eq 0) "uninstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    $ml = ML $s
    Check ($ml -contains "+$sss24") "player's own SSS24 tick kept"
    Check ($ml -contains "+$mt" -and $ml -contains "-$sss23") "the other reverted lines put back"
    Check ((T "$r\Anomaly\bin\sl.interposer.dll") -eq 'sss24 sl 2.11.1 sl.interposer.dll') "DLLs back"
    $script:scenario = 'S27b_reinstall_after_retick'
    $s = New-Scenario 'S27b_reinstall_after_retick'
    New-Sss24Setup $s
    [void](Install $s)
    W "$($s.Root)\$mlRel" ((((ML $s) -join "`r`n") -replace [regex]::Escape("-$sss24"), "+$sss24") + "`r`n")
    $c = Install $s
    Check ($c -eq 0) "reinstall exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ($script:lastOut -match 'SSS24 found') "SSS24 found again"
    Check ((ML $s) -contains "-$sss24") "unticked again"
}

$scenarios['S28_sss24_killed_halfway'] = {
    $s = New-Scenario 'S28_sss24_killed_halfway'
    New-Sss24Setup $s
    $pre = Snap $s.Root
    # 8 engine files (STEP 1, 7, 6 for an RTX 3060), then the DLL moves: dies after 2 of them
    $env:SLOPRAY_TEST_KILL_AFTER = '10'
    $c = Install $s
    Remove-Item Env:\SLOPRAY_TEST_KILL_AFTER
    Check ($c -eq 3) "killed (got $c)"
    $j = Get-ChildItem -LiteralPath "$($s.Root)\.slopray\runs" -Recurse -Filter journal.jsonl | Get-Content -Raw
    Check ($j -match 'sl\.[a-z]+\.dll' -and $j -notmatch '"op":\s*"text"') "killed inside the revert, before the modlist write"
    $c = Install $s
    Check ($c -eq 0) "next run undid it (got $c)"; Show-OnFail ($c -eq 0)
    $d = Compare-Snap $pre (Snap $s.Root)
    Check ($d.Count -eq 0) "back exactly as before ($($d -join ', '))"
}

# --- SSS 23.5 required (any install, with or without SSS24) --------------------
$scenarios['S29_no_sss235_ticked'] = {
    $s = New-Scenario 'S29_no_sss235_ticked'
    W "$($s.Root)\$mlRel" ((((ML $s) -replace "^\+$([regex]::Escape($sss23))$", "-$sss23") -join "`r`n") + "`r`n")
    Assert-Refused $s 'SSS 23\.5' 'SSS 23 unticked'
}

$scenarios['S29b_old_sss_above_235'] = {
    $s = New-Scenario 'S29b_old_sss_above_235'
    W "$($s.Root)\GAMMA\mods\190- Screen Space Shaders latest - Ascii1457\gamedata\shaders\r3\screenspace_reflections.h" $sigOld
    Add-ModLine $s '+190- Screen Space Shaders latest - Ascii1457'     # top = highest priority
    Assert-Refused $s 'Screen Space Shaders latest' 'older SSS wins over 23.5'
}

$scenarios['S29c_old_sss_below_235_and_atmos'] = {
    $s = New-Scenario 'S29c_old_sss_below_235_and_atmos'
    $r = $s.Root
    W "$r\GAMMA\mods\190- Screen Space Shaders latest - Ascii1457\gamedata\shaders\r3\screenspace_reflections.h" $sigOld
    W "$r\GAMMA\mods\Atmos RC8\gamedata\shaders\r3\screenspace_reflections.h" $sigAtmos
    W "$r\$mlRel" (((ML $s) -join "`r`n") + "`r`n+190- Screen Space Shaders latest - Ascii1457`r`n")   # bottom = lowest priority
    Add-ModLine $s '+Atmos RC8'                                          # wins over 23.5, built for it
    $c = Install $s
    Check ($c -eq 0) "exit 0 (got $c)"; Show-OnFail ($c -eq 0)
    Check ($script:lastOut -match 'SSS 23\.5: ok') "says SSS 23.5 is fine"
}

# --- run ---------------------------------------------------------------------
Write-Host "Slop-Ray installer tests in $base"
foreach ($k in $scenarios.Keys) {
    if ($Only -and $k -notlike "$Only*") { continue }
    try { & $scenarios[$k] } catch { $script:failed.Add("$k crashed: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"); Write-Host "    CRASH: $($_.Exception.Message)" -ForegroundColor Red }
}
Write-Host ""
Write-Host "passed checks: $passed   failed: $($failed.Count)"
foreach ($f in $failed) { Write-Host "  $f" -ForegroundColor Red }
if (-not $Keep -and -not $failed.Count) {
    # only our own %TEMP% test folder
    cmd /c rmdir /s /q "$base" | Out-Null
} else { Write-Host "fixtures kept in $base" }
exit $(if ($failed.Count) { 1 } else { 0 })
