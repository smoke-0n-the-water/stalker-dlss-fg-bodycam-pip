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

function New-Gamma ($root) {
    W "$root\Anomaly\bin\AnomalyDX11AVX.exe" 'GAMMA original dx11'
    W "$root\Anomaly\bin\other.dll" 'unrelated dll'
    W "$root\Anomaly\db\mods\00_modded_exes_gamedata.db0" 'GAMMA original db0'
    W "$root\Anomaly\db\other.db0" 'unrelated db'
    W "$root\Anomaly\appdata\user.ltx" "r3_msaa st_opt_4x`r`nrs_v_sync on`r`nmouse_sens 0.12`r`n"
    W "$root\Anomaly\appdata\shaders_cache\r3\x.bin" 'cache'
    W "$root\GAMMA\ModOrganizer.ini" "[General]`r`nselected_profile=@ByteArray(Test Profile)`r`n[customExecutables]`r`nsize=1`r`n1\title=Anomaly (DX11-AVX)`r`n1\binary=C:/x/AnomalyDX11AVX.exe`r`n[Settings]`r`nfoo=bar`r`n"
    W "$root\GAMMA\profiles\Test Profile\modlist.txt" "# This file was automatically generated by Mod Organizer.`r`n+My Own Mod`r`n+410- 3DSS for GAMMA`r`n+Bodycam-GAMMA-Patch-2.0.1`r`n-Disabled Mod`r`n+Anti_Lag_for_GAMMA 1.2`r`n"
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
function Diff ($a, $b) {
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

# allowed to differ after a full uninstall: the shader cache (moved into
# .slopray, the game rebuilds it) and the two tool .bat files we leave behind
function Assert-BackToOriginal ($pre, $root, $what) {
    $d = Diff $pre (Snap $root)
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
    Check ((Diff $pre (Snap $s.Root)).Count -eq 0) "dry run changed nothing"
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
    $d = @((Diff $pre (Snap $r)) | Where-Object {
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
    W $mlp "# This file was automatically generated by Mod Organizer.`r`n+3 - Test Compat (0.71)`r`n+My Own Mod`r`n+410- 3DSS for GAMMA`r`n-Bodycam-GAMMA-Patch-2.0.1`r`n-Disabled Mod`r`n+Anti_Lag_for_GAMMA 1.2`r`n"
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
    $d = @((Diff $a (Snap $s.Root)) | Where-Object { $_ -ne '~Anomaly\appdata\user.ltx' })
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
    $d = Diff $pre (Snap $s.Root)
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
        $d = Diff $pre (Snap $s.Root)
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
    Check ((Diff $a (Snap $s.Root)).Count -eq 0) "second uninstall changed nothing"
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
    Check ((Diff $pre (Snap $s.Root)).Count -eq 0) "undone"
    $s = New-Scenario 'S16b_junction'
    $outside = "$base\outside_target"
    [void][IO.Directory]::CreateDirectory($outside)
    cmd /c mklink /J "$($s.Root)\Anomaly\bin\streamline" "$outside" | Out-Null
    $pre = Snap $s.Root
    $c = Install $s
    Check ($c -eq 1) "install refused through a junction (got $c)"; Show-OnFail ($c -eq 1)
    Check (-not (Get-ChildItem -LiteralPath $outside -Force)) "nothing written through the junction"
    Check ((Diff $pre (Snap $s.Root)).Count -eq 0) "undone"
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
