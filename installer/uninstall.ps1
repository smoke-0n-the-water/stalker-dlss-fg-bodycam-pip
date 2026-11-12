# ===========================================================================
#  Slop-Ray Engine uninstaller. PLAIN TEXT, read it in Notepad first.
#
#  Puts your GAMMA install back the way it was before Slop-Ray, using the
#  record the installer wrote (GAMMA\.slopray\record.json). For every file:
#    - ours and unchanged since install       -> your original is put back
#                                                (or the file removed, if
#                                                there was none before)
#    - changed by you after install           -> left as is, or moved to
#                                                GAMMA\.slopray\recovery
#    - original backup missing or damaged     -> left as is, reported
#  MO2 mod list, launch entry and user.ltx: only what the installer set, and
#  only where you have not changed it since. Your backups are kept.
#  When in doubt, your current file is kept.
#     -DryRun   show what would happen, change nothing
#     -Yes      don't ask
#     -GamePath "D:\Games\S.T.A.L.K.E.R. GAMMA"   skip auto-detection
# ===========================================================================
[CmdletBinding()]
param(
    [string]$GamePath,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\SlopRay.psm1" -Force -DisableNameChecking
$fail = 0
$logTmp = "$env:TEMP\slopray_uninstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
Say "  Slop-Ray Engine uninstaller"
if ($DryRun) { Say "  *** DRY RUN - nothing will be changed ***" }
Say "==================================================================="

Head "Checking the game and MO2 are closed"
$busy = Get-BusyGameProcesses
if ($busy) {
    if ($DryRun) { Warn "$($busy -join ', ') is open. Fine for -DryRun, close it before a real run." }
    else { Bad "Close these first, then run me again: $($busy -join ', ')"; Pause-End 1 }
} else { Good "closed" }

Head "Finding your STALKER GAMMA folder"
try { $root = (Find-GammaRoot $GamePath $here).TrimEnd('\') } catch { Bad $_.Exception.Message; Pause-End 1 }
Good "found: $root"
$modsDir = "$root\GAMMA\mods"
try { $sr = Open-SlopRay $root "$here\catalogue.json" } catch { Bad $_.Exception.Message; Pause-End 1 }

if ($sr.WasNew -or $sr.Record.state -eq 'new') {
    $old = @('Anomaly\bin\AnomalyDX12.exe', 'Anomaly\bin\AnomalyDX11AVX.exe') |
           Where-Object { (Test-Path -LiteralPath "$root\$_") -and $sr.Cat.Contains((Get-Sha "$root\$_")) }
    if ($old) {
        Warn "Slop-Ray files are here, but no install record (an older pack installed them)."
        Say "  Run the new installer once: it takes over the old install safely and"
        Say "  records your originals (your .old files). Then run this uninstaller."
        Say "  By hand instead: see ROLLBACK in 'READ ME FIRST.txt'."
        Pause-End 1
    }
    Good "Slop-Ray is not installed here - nothing to do"
    Pause-End 0
}
if ($sr.Record.state -eq 'installing') {
    Head "An install did not finish"
    Say "  I can undo what it changed. Run the uninstaller again afterwards if"
    Say "  an earlier, finished install is still there."
    if ($DryRun) { Pause-End 0 }
    if (-not (Confirm-Go "Undo the unfinished install now?")) { Pause-End 1 }
    $problems = Undo-Run $sr $sr.Record.runId
    foreach ($p in $problems) { Warn $p }
    if ($problems.Count) { Bad "undo left $($problems.Count) thing(s) to check (above)" } else { Good "undone" }
    Pause-End $(if ($problems.Count) { 1 } else { 0 })
}

# --- plan: nothing is changed in this part --------------------------------
Head "Checking every file Slop-Ray installed"
$rels = @($sr.Record.files.Keys | Where-Object { $sr.Record.files[$_].installedHash -and -not $sr.Record.files[$_].keep } | Sort-Object)
$plan = @{}
foreach ($rel in $rels) {
    $c = Restore-OwnedFile $sr $rel -Plan
    if (-not $plan[$c]) { $plan[$c] = New-Object System.Collections.Generic.List[string] }
    $plan[$c].Add($rel)
}
function N ($c) { if ($plan[$c]) { $plan[$c].Count } else { 0 } }

# settings the installer set that are still as it set them
$exe = $sr.Record.exe
$keysToRevert = @($sr.Record.keys.Keys | Where-Object { $null -ne $sr.Record.keys[$_].written })
$mlToRevert = 0
foreach ($ml in $sr.Record.modlist.Keys) { foreach ($n in $sr.Record.modlist[$ml].Keys) { if ($null -ne $sr.Record.modlist[$ml][$n].written) { $mlToRevert++ } } }

# v0.5.0-dev's 3DSS merge: swap GAMMA's own 410 folder back
$swap = $null
$legacy = $sr.Record.legacy3dss
if ($legacy -and -not $legacy.swapped) {
    $bk = "$root\$($legacy.backup)"
    $src = $null
    if (Test-Path -LiteralPath "$bk\gamedata") { $src = $bk }
    else {
        $subs = @(Get-ChildItem -LiteralPath $bk -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath "$($_.FullName)\gamedata" })
        if ($subs.Count -eq 1) { $src = $subs[0].FullName }
    }
    $cur = Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '410- 3DSS for GAMMA*' } | Select-Object -First 1
    if ($src -and $cur -and (Test-Path -LiteralPath "$($cur.FullName)\gamedata\scripts\z_3dss_lens_hider.script") -and
        (Test-Path -LiteralPath "$src\gamedata\scripts\lewd_lens_hider.script")) {
        $swap = @{ Src = $src; Cur = $cur.FullName; Name = $cur.Name; Bk = $bk }
    }
}

if ($sr.Record.state -eq 'uninstalled' -and (N 'A restored') + (N 'C removed') + (N 'D recovered') -eq 0 -and
    $keysToRevert.Count -eq 0 -and $mlToRevert -eq 0 -and -not ($exe -and $exe.written) -and -not $swap) {
    Good "already uninstalled - nothing left to do"
    $kept = (N 'B kept') + (N 'E kept') + (N 'U kept')
    if ($kept) { Warn "$kept file(s) still need you - see the last report in $($sr.Dir)\logs" }
    Pause-End 0
}

Head "What I will do"
Say "  put your originals back : $(N 'A restored')"
Say "  remove files we added   : $(N 'C removed')"
Say "  move to recovery folder : $(N 'D recovered')  (files we added that you changed since)"
Say "  keep as they are        : $((N 'B kept') + (N 'E kept') + (N 'U kept'))  (listed in the report)"
Say "  already back to normal  : $(N 'done')"
Say "  MO2 mod list lines      : $mlToRevert to put back (only ones you haven't changed)"
Say "  user.ltx settings       : $($keysToRevert.Count) to put back (only ones you haven't changed)"
if ($exe -and $exe.written) { Say "  MO2 launch entry        : remove '$($exe.title)'" }
if ($swap) { Say "  3DSS                    : put GAMMA's own 410 folder back from GAMMA\3DSS_backup" }
elseif ($legacy -and -not $legacy.swapped) { Say "  3DSS                    : GAMMA\3DSS_backup left alone (current 410 is not the v0.5.0-dev merge)" }
Say "  your backups            : kept in $($sr.Dir)\backup"
if ($DryRun) { Say ""; Say "  DRY RUN COMPLETE - nothing was changed"; Pause-End 0 }
Say ""
if (-not (Confirm-Go "Uninstall now?")) { Say "  Cancelled - nothing was changed."; Pause-End 1 }

# --- uninstall ---------------------------------------------------------------
Start-Run $sr 'uninstall' ''
$result = @{}
$attention = New-Object System.Collections.Generic.List[string]
try {
    Head "Restoring files"
    foreach ($rel in $rels) {
        $c = Restore-OwnedFile $sr $rel
        if (-not $result[$c]) { $result[$c] = New-Object System.Collections.Generic.List[string] }
        $result[$c].Add($rel)
    }
    foreach ($c in 'A restored', 'C removed', 'D recovered', 'B kept', 'E kept', 'U kept', 'done') {
        if ($result[$c]) { Good "$c : $($result[$c].Count)" }
    }
    foreach ($rel in $result['B kept'])  { $attention.Add("KEPT (you changed it after install; original is in .slopray\backup\$rel): $rel") }
    foreach ($rel in $result['E kept'])  { $attention.Add("KEPT (original backup missing or damaged; reinstall GAMMA's copy, e.g. GAMMA launcher update): $rel") }
    foreach ($rel in $result['U kept'])  { $attention.Add("KEPT (an older pack never saved your original; GAMMA launcher update restores GAMMA's own files): $rel") }
    foreach ($rel in $result['D recovered']) { $attention.Add("MOVED to .slopray\recovery\$($sr.Run.Id)\$rel (a file we added that you changed)") }

    # folders the installer created, if they are empty now (never anything inside)
    $left = @()
    foreach ($d in @($sr.Record.dirs | Sort-Object { $_.Length } -Descending)) {
        $p = Resolve-Rel $sr $d
        if ((Test-Path -LiteralPath $p) -and -not (Get-ChildItem -LiteralPath $p -Force | Select-Object -First 1)) { [IO.Directory]::Delete($p) }
        if (Test-Path -LiteralPath $p) { $left += $d }
    }
    $sr.Record.dirs = $left

    Head "MO2 mod list"
    foreach ($ml in @($sr.Record.modlist.Keys)) {
        $rec = $sr.Record.modlist[$ml]
        $p = Resolve-Rel $sr $ml
        if (-not (Test-Path -LiteralPath $p)) { $attention.Add("MO2 profile gone, mod list not touched: $ml"); continue }
        $ls = [IO.File]::ReadAllLines($p, $Utf8)
        $cur = Get-ModlistState $ls
        $out = New-Object System.Collections.Generic.List[string]
        $changed = $false
        foreach ($l in $ls) {
            $n = $(if ($l.Length -ge 2 -and ("$($l[0])" -eq '+' -or "$($l[0])" -eq '-')) { $l.Substring(1) } else { $null })
            $e = $(if ($n) { $rec[$n] } else { $null })
            if (-not $e -or $null -eq $e.written) { $out.Add($l); continue }
            if ($cur[$n] -ne $e.written) {
                Say "  you changed '$n' since install - left as is"
                $e.written = $null; $out.Add($l); continue
            }
            $e.written = $null; $changed = $true
            $gone = -not (Test-Path -LiteralPath "$modsDir\$n")
            if ($gone) { Say "  removed from list: $n"; continue }
            if ($null -eq $e.baseline) { $out.Add("-$n"); $attention.Add("MO2: '$n' still has files in it (yours or changed), unticked instead of removed") }
            else { $out.Add("$($e.baseline)$n"); Say "  put back: $($e.baseline)$n" }
        }
        # lines the installer removed (old pack mods) are not added back: their folders are gone
        foreach ($n in @($rec.Keys)) { if ($null -ne $rec[$n].written) { $rec[$n].written = $null } }
        if ($changed) { Set-TextFile $sr $ml ((@($out) -join "`r`n") + "`r`n") }
        Good "$ml"
    }

    Head "MO2 launch entry"
    if ($exe -and $exe.written) {
        $p = Resolve-Rel $sr $exe.file
        $il = @([IO.File]::ReadAllLines($p, $Utf8))
        # find our entry: same title AND same exe path as the installer wrote
        $idx = $null; $inSec = $false
        $titles = @{}; $bins = @{}
        foreach ($l in $il) {
            if ($l -match '^\[(.+)\]$') { $inSec = ($Matches[1] -eq 'customExecutables'); continue }
            if ($inSec -and $l -match '^(\d+)\\title=(.*)$')  { $titles[$Matches[1]] = $Matches[2] }
            if ($inSec -and $l -match '^(\d+)\\binary=(.*)$') { $bins[$Matches[1]] = $Matches[2] }
        }
        foreach ($i in $titles.Keys) { if ($titles[$i] -eq $exe.title -and $bins[$i] -eq $exe.binary) { $idx = [int]$i } }
        if ($null -eq $idx) {
            $attention.Add("MO2 launch entry '$($exe.title)' was changed or removed by you - left as is")
        } else {
            $out = New-Object System.Collections.Generic.List[string]
            $inSec = $false
            foreach ($l in $il) {
                if ($l -match '^\[(.+)\]$') { $inSec = ($Matches[1] -eq 'customExecutables'); $out.Add($l); continue }
                if ($inSec -and $l -match '^size=(\d+)\s*$') { $out.Add("size=$([int]$Matches[1] - 1)"); continue }
                if ($inSec -and $l -match '^(\d+)\\(.*)$') {
                    $i = [int]$Matches[1]
                    if ($i -eq $idx) { continue }
                    if ($i -gt $idx) { $out.Add("$($i - 1)\$($Matches[2])"); continue }
                }
                $out.Add($l)
            }
            Set-TextFile $sr $exe.file (($out -join "`r`n") + "`r`n")
            Good "removed '$($exe.title)'"
        }
        $exe.written = $false
    } else { Good "nothing to do" }

    Head "Video settings (user.ltx)"
    $byFile = $keysToRevert | Group-Object { $sr.Record.keys[$_].file }
    foreach ($g in $byFile) {
        $p = Resolve-Rel $sr $g.Name
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $ul = New-Object System.Collections.Generic.List[string]
        $ul.AddRange([string[]][IO.File]::ReadAllLines($p))
        $changed = $false
        foreach ($ek in $g.Group) {
            $e = $sr.Record.keys[$ek]
            $i = -1
            for ($j = 0; $j -lt $ul.Count; $j++) { if ($ul[$j] -match "^$([regex]::Escape($e.key))\s") { $i = $j; break } }
            if ($i -ge 0 -and $ul[$i] -eq $e.written) {
                if ($null -eq $e.baseline) { $ul.RemoveAt($i) } else { $ul[$i] = $e.baseline }
                $changed = $true
                Good "$($e.key): put back$(if ($e.baseline) { " ($($e.baseline))" })"
            } else { Say "  $($e.key): you changed it since install - left as is" }
            $e.written = $null
        }
        if ($changed) { Set-TextFile $sr $g.Name (($ul -join "`r`n") + "`r`n") }
    }

    if ($swap) {
        Head "3DSS"
        [void](Resolve-Rel $sr (Get-Rel $sr $swap.Cur)); [void](Resolve-Rel $sr (Get-Rel $sr $swap.Src))
        $parked = Get-RecoveryPath $sr "GAMMA\mods\$($swap.Name)"
        Move-DirLogged $sr $swap.Cur $parked
        Move-DirLogged $sr $swap.Src $swap.Cur
        if ($swap.Src -ne $swap.Bk) { Remove-EmptyDirs $null $swap.Bk -IncludeTop }
        $legacy.swapped = $true
        Good "GAMMA's own 410 folder is back. The 5.02 merge is in $parked"
        $attention.Add("3DSS: the v0.5.0-dev 5.02 merge was moved to $parked")
    }

    $complete = -not ($result['B kept'] -or $result['E kept'] -or $result['U kept'])
    $report = "$($sr.Dir)\logs\uninstall_report_$($sr.Run.Id).txt"
    [void][IO.Directory]::CreateDirectory("$($sr.Dir)\logs")
    $txt = @("Slop-Ray uninstall $(Get-Date -Format s)", "GAMMA folder: $root",
             "Result: $(if ($complete) { 'COMPLETE - everything Slop-Ray changed is back as it was' } else { 'PARTLY - some files need you (below)' })", "")
    foreach ($c in $result.Keys | Sort-Object) { $txt += "$c : $($result[$c].Count)"; foreach ($r in $result[$c]) { $txt += "    $r" } }
    $txt += ""; $txt += "NEEDS YOUR ATTENTION:"; $txt += $(if ($attention.Count) { $attention } else { "  nothing" })
    $txt += ""; $txt += "Backups kept: $($sr.Dir)\backup  (remove later with 'CLEAN UP BACKUPS - Slop-Ray Engine.bat')"
    [IO.File]::WriteAllLines($report, $txt, $Utf8)
    Complete-Run $sr 'uninstalled' @{ complete = $complete }
} catch {
    Bad "uninstall stopped: $($_.Exception.Message)"
    Say "  Nothing was deleted that wasn't checked first. Your backups are in $($sr.Dir)\backup."
    Say "  Run the uninstaller again: it carries on where it stopped."
    Pause-End 1
}

Say ""
Say "==================================================================="
if ($complete) { Write-Host "  UNINSTALLED - your GAMMA install is back as it was" -ForegroundColor Green }
else { Write-Host "  UNINSTALLED, BUT $($attention.Count) THING(S) NEED YOU - see below" -ForegroundColor Yellow }
Say "==================================================================="
foreach ($a in $attention) { Warn $a }
Say ""
Say "  report : $report"
Say "  backups: $($sr.Dir)\backup (kept)"
if ($sr.Record.shaderCache.baseline) { Say "  your shader cache from before Slop-Ray: $($sr.Record.shaderCache.baseline) (the game rebuilds its own)" }
Say "  Launch GAMMA with the normal DX11 entry in MO2."
Pause-End $(if ($complete) { 0 } else { 2 })
