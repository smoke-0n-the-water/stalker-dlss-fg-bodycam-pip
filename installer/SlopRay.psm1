# ===========================================================================
#  SlopRay.psm1 - the safe file layer shared by install.ps1, uninstall.ps1
#  and cleanup_backups.ps1. PLAIN TEXT, read it in Notepad if you like.
#
#  Every change to the game folder goes through here so it is:
#    - kept inside the GAMMA folder (no "..", no links or junctions followed)
#    - backed up before anything of yours is replaced (moved, never deleted)
#    - written to the install record (<GAMMA>\.slopray\record.json)
#    - written to the run's journal first, so an interrupted run can be undone
#
#  Words used below (see CONTEXT.md):
#    Baseline  = what a path looked like before the FIRST Slop-Ray install.
#                "present" (kept in .slopray\backup), "absent", or "unknown".
#    Drift     = the file changed after we wrote it. Never overwritten or
#                deleted: it is moved to .slopray\recovery or left in place.
#
#  Test hooks (only used by tests\run.ps1):
#    SLOPRAY_TEST_NO_PROCESS_CHECK=1   skip the "is MO2 open" check
#    SLOPRAY_TEST_FAIL_AFTER=N         throw after N file operations
#    SLOPRAY_TEST_KILL_AFTER=N         end the process after N file operations
#    SLOPRAY_TEST_HAGS=0|1|2|missing   pretend this HwSchMode (no registry read)
# ===========================================================================

$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-Sha ([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Get-ShaText ([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    (($sha.ComputeHash($Utf8.GetBytes($Text)) | ForEach-Object { $_.ToString('X2') }) -join '')
}

# ConvertFrom-Json gives PSCustomObjects; the record is easier to edit as hashtables
function ConvertTo-Hash ($o) {
    if ($null -eq $o) { return $null }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }
        return $h
    }
    if ($o -is [array]) { return , @($o | ForEach-Object { ConvertTo-Hash $_ }) }
    return $o
}

function Write-FileAtomic ([string]$Path, [string]$Text) {
    $tmp = "$Path.sr-tmp"
    [IO.File]::WriteAllText($tmp, $Text, $Utf8)
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
}

# --- finding the game ------------------------------------------------------
# An install is two folders: Anomaly (bin\AnomalyDX11AVX.exe + db) and the
# G.A.M.M.A. MO2 folder (ModOrganizer.ini + mods + profiles). Usually they sit
# side by side as <folder>\Anomaly + <folder>\GAMMA ("standard"). Some players
# keep them apart ("split", e.g. E:\Anomaly + E:\GAMMA\GAMMA RC3); MO2's own
# gamePath setting says where its Anomaly is.
# Join-Path THROWS on a drive letter that does not exist: build plain strings
# and wrap every test, so a missing D: is just "no".

# selected_profile / gamePath are stored by Qt as @ByteArray(...) with \xHH escapes
# for non-ASCII bytes (e.g. a Greek letter becomes \xce\x94) and \\ for a backslash.
function Decode-QtValue ($v) {
    $v = $v.Trim()
    if ($v -match '^@ByteArray\((.*)\)$') { $v = $Matches[1] }
    $bytes = New-Object System.Collections.Generic.List[byte]
    $i = 0
    while ($i -lt $v.Length) {
        $c = $v[$i]
        if ($c -eq '\' -and $i + 1 -lt $v.Length) {
            $n = $v[$i + 1]
            if ($n -eq 'x') {
                $hex = ''
                $j = $i + 2
                while ($j -lt $v.Length -and $hex.Length -lt 2 -and "$($v[$j])" -match '^[0-9a-fA-F]$') { $hex += $v[$j]; $j++ }
                if ($hex.Length -gt 0) { $bytes.Add([Convert]::ToByte($hex, 16)); $i = $j; continue }
            }
            if ($n -eq '\' -or $n -eq '"') { $bytes.Add([byte][char]$n); $i += 2; continue }
        }
        foreach ($b in $Utf8.GetBytes("$c")) { $bytes.Add($b) }
        $i++
    }
    $Utf8.GetString($bytes.ToArray())
}

# full path without a trailing backslash; a drive root is "C:" (never ".NET's current dir on C:")
function Get-NormPath ([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $t = $Path.Trim().Trim('"').Trim().Replace('/', '\')
        if ($t -match '^[A-Za-z]:$') { $t = "$t\" }
        return [IO.Path]::GetFullPath($t).TrimEnd('\')
    } catch { return $null }
}
function Get-ParentPath ([string]$Path) {
    if (-not $Path -or $Path -match '^[A-Za-z]:$') { return $null }     # a drive has no parent
    Get-NormPath (Split-Path -Parent "$Path\")
}
function Test-AnomalyDir ($d) {
    if (-not $d) { return $false }
    try { (Test-Path -LiteralPath "$d\bin\AnomalyDX11AVX.exe") -and (Test-Path -LiteralPath "$d\db") } catch { $false }
}
function Test-Mo2Dir ($d) {
    if (-not $d) { return $false }
    try { (Test-Path -LiteralPath "$d\ModOrganizer.ini") -and (Test-Path -LiteralPath "$d\mods") -and (Test-Path -LiteralPath "$d\profiles") } catch { $false }
}
function Get-Mo2GamePath ($Mo2) {
    try {
        $line = [IO.File]::ReadAllLines("$Mo2\ModOrganizer.ini", $Utf8) | Where-Object { $_ -match '^gamePath=' } | Select-Object -First 1
        if ($line) { return Get-NormPath (Decode-QtValue $line.Substring('gamePath='.Length)) }
    } catch { }
    return $null
}
# Home = where .slopray and the uninstaller .bat live: the shared folder in the
# standard layout, the Anomaly folder in a split one.
function New-GammaInstall ([string]$Anomaly, [string]$Mo2) {
    $a = Get-NormPath $Anomaly; $m = Get-NormPath $Mo2
    $pa = Get-ParentPath $a
    $standard = $pa -and ($pa -ieq (Get-ParentPath $m)) -and ((Split-Path -Leaf $a) -ieq 'Anomaly') -and ((Split-Path -Leaf $m) -ieq 'GAMMA')
    @{ Anomaly = $a; Mo2 = $m; Home = $(if ($standard) { $pa } else { $a }); Split = -not $standard }
}
# A typed folder can be the shared folder, the Anomaly folder, the MO2 folder, or a
# folder with a Slop-Ray record. Returns an install, or $null.
function Resolve-GammaInstall ([string]$Path) {
    $x = Get-NormPath $Path
    if (-not $x) { return $null }
    try {
        $rp = "$x\.slopray\record.json"
        if (Test-Path -LiteralPath $rp) {
            $rec = Get-Content -LiteralPath $rp -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($rec.anomaly -and $rec.mo2 -and (Test-AnomalyDir $rec.anomaly) -and (Test-Mo2Dir $rec.mo2)) { return New-GammaInstall $rec.anomaly $rec.mo2 }
        }
    } catch { }
    $px = Get-ParentPath $x
    $mo2 = @($x, "$x\GAMMA", $(if ((Test-AnomalyDir $x) -and $px) { "$px\GAMMA" })) |
           Where-Object { Test-Mo2Dir $_ } | Select-Object -First 1
    if (-not $mo2) { return $null }
    $an = Get-Mo2GamePath $mo2           # where MO2 really starts the game from
    if (-not (Test-AnomalyDir $an)) {
        $pm = Get-ParentPath $mo2
        $an = @("$x\Anomaly", $x, $(if ($pm) { "$pm\Anomaly" })) | Where-Object { Test-AnomalyDir $_ } | Select-Object -First 1
    }
    if ($an) { return New-GammaInstall $an $mo2 }
    return $null
}
# why a folder is not a complete install, in words a player understands
function Get-GammaProblem ([string]$Path) {
    $x = Get-NormPath $Path
    if (-not $x -or -not (Test-Path -LiteralPath $x)) { return "'$Path' does not exist." }
    $an = @("$x\Anomaly", $x) | Where-Object { Test-AnomalyDir $_ } | Select-Object -First 1
    $mo2 = @($x, "$x\GAMMA") | Where-Object { Test-Mo2Dir $_ } | Select-Object -First 1
    if ($an -and -not $mo2) {
        return "found Anomaly in '$an', but no G.A.M.M.A. MO2 folder (ModOrganizer.ini + mods + profiles) next to it. " +
               "Install G.A.M.M.A. first. If it is somewhere else, give me the GAMMA folder that has ModOrganizer.ini."
    }
    if ($mo2 -and -not $an) {
        return "found the G.A.M.M.A. MO2 folder '$mo2', but not its Anomaly folder (bin\AnomalyDX11AVX.exe + db). " +
               "Its game path is '$(Get-Mo2GamePath $mo2)'. Finish the G.A.M.M.A. install first, or give me the folder that holds Anomaly."
    }
    return "'$x' has no G.A.M.M.A. install (looked for Anomaly\bin\AnomalyDX11AVX.exe and GAMMA\ModOrganizer.ini + mods + profiles). Install G.A.M.M.A. first."
}
function Find-GammaInstalls {
    $test = $env:SLOPRAY_TEST_SEARCH_ONLY      # tests: only these folders, no drive search
    $candidates = @()
    $drives = @()
    if ($test) { $candidates = $test.Split(';') }
    else {
        try {
            $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                      Where-Object { $_.Root -match '^[A-Za-z]:\\$' } | ForEach-Object { $_.Root.TrimEnd('\') }
        } catch { }
        if (-not $drives) { $drives = @($env:SystemDrive) }
        foreach ($d in $drives) {
            foreach ($sub in 'Program Files (x86)\GOG Galaxy\Games\S.T.A.L.K.E.R. GAMMA', 'Program Files\GOG Galaxy\Games\S.T.A.L.K.E.R. GAMMA',
                             'GOG Galaxy\Games\S.T.A.L.K.E.R. GAMMA', 'Program Files (x86)\Steam\steamapps\common\S.T.A.L.K.E.R. GAMMA',
                             'SteamLibrary\steamapps\common\S.T.A.L.K.E.R. GAMMA', 'S.T.A.L.K.E.R. GAMMA', 'STALKER GAMMA', 'GAMMA',
                             'Games\S.T.A.L.K.E.R. GAMMA', 'Games\STALKER GAMMA', 'Games\GAMMA', 'STALKER MODS\S.T.A.L.K.E.R. GAMMA') {
                $candidates += "$d\$sub"
            }
            $candidates += $d                  # the game straight on a drive (C:\Anomaly + C:\GAMMA)
        }
    }
    $found = [ordered]@{}
    foreach ($c in $candidates) {
        $i = Resolve-GammaInstall $c
        if ($i) { $found["$($i.Anomaly)|$($i.Mo2)".ToLowerInvariant()] = $i }
    }
    if (-not $found.Count -and -not $test) {
        Write-Host "  not in the usual places - searching drives $($drives -join ' ') (a minute or two)"
        foreach ($d in $drives) {
            foreach ($pat in 'AnomalyDX11AVX.exe', 'ModOrganizer.ini') {
                try {
                    $hits = @(Get-ChildItem -LiteralPath "$d\" -Filter $pat -Recurse -Depth 5 -File -Force -ErrorAction SilentlyContinue)
                } catch { $hits = @() }
                foreach ($h in $hits) {
                    $dir = Split-Path -Parent $h.FullName
                    if ($pat -eq 'AnomalyDX11AVX.exe') { $dir = Split-Path -Parent $dir }      # bin -> Anomaly
                    $i = Resolve-GammaInstall $dir
                    if ($i) { $found["$($i.Anomaly)|$($i.Mo2)".ToLowerInvariant()] = $i }
                }
            }
        }
    }
    return , @($found.Values)
}
function Show-GammaInstall ($i) {
    if ($i.Split) { "Anomaly: $($i.Anomaly)   G.A.M.M.A. (MO2): $($i.Mo2)" } else { $i.Home }
}
# Picks the install to work on, or throws with a message for the player.
#   -GamePath   never second-guessed (a typo must not land in another install)
#   -Ask        skip the search and ask for a folder (INSTALL - choose folder.bat)
#   -NoPrompt   never ask (-Yes): more than one install, or none, is an error
function Select-GammaInstall ([string]$GamePath, [string]$From, [switch]$Ask, [switch]$NoPrompt) {
    if ($GamePath) {
        $i = Resolve-GammaInstall $GamePath
        if (-not $i) { throw (Get-GammaProblem $GamePath) }
        return $i
    }
    if (-not $Ask) {
        # the folder this runs from wins (the uninstaller in <game>\.slopray\tool, a pack unzipped into the game)
        $p = Get-NormPath $From
        for ($n = 0; $n -lt 3 -and $p; $n++) {
            $i = Resolve-GammaInstall $p
            if ($i) { return $i }
            $p = Get-ParentPath $p
        }
        $found = Find-GammaInstalls
        if ($found.Count -eq 1) { return $found[0] }
        if ($found.Count -gt 1) {
            Write-Host "  found more than one G.A.M.M.A. install:"
            for ($k = 0; $k -lt $found.Count; $k++) { Write-Host "    $($k + 1). $(Show-GammaInstall $found[$k])" }
            if ($NoPrompt) { throw "more than one G.A.M.M.A. install found (listed above). Run again with -GamePath and the one you want." }
            while ($true) {
                $ans = $null
                try { $ans = Read-Host "Which one? Type its number (1-$($found.Count))" } catch { throw "no choice made - run again with -GamePath" }
                if ($ans -match '^\s*(\d+)\s*$' -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -le $found.Count) { return $found[[int]$Matches[1] - 1] }
                Write-Host "  Type a number from the list."
            }
        }
        Write-Host "  no complete G.A.M.M.A. install found in the usual places."
        if ($NoPrompt) { throw "no G.A.M.M.A. install found. Install G.A.M.M.A. first, or run again with -GamePath." }
    }
    while ($true) {
        Write-Host ""
        Write-Host "Open your G.A.M.M.A. folder in Explorer, copy the address bar and paste it here"
        Write-Host "(right-click pastes). The folder with 'Anomaly' and 'GAMMA' in it, or either of those two."
        Write-Host "Example:  G:\STALKER MODS\S.T.A.L.K.E.R. GAMMA"
        $typed = $null
        try { $typed = Read-Host "Path" } catch { throw "no folder given - run again with -GamePath" }
        $i = Resolve-GammaInstall $typed
        if ($i) { return $i }
        Write-Host "  $(Get-GammaProblem $typed)"
    }
}

function Get-BusyGameProcesses {
    if ($env:SLOPRAY_TEST_NO_PROCESS_CHECK) { return @() }
    @(Get-Process -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^(Anomaly|ModOrganizer|usvfs|xrEngine)' } |
      Select-Object -Expand Name -Unique)
}

# Hardware-accelerated GPU scheduling: HwSchMode 2 = on, 1 = off, missing = the GPU/driver has no switch.
# Read only, never written. Returns $null when the value is missing.
function Get-HwSchMode {
    if ($env:SLOPRAY_TEST_HAGS) { if ($env:SLOPRAY_TEST_HAGS -eq 'missing') { return $null } else { return [int]$env:SLOPRAY_TEST_HAGS } }
    try { return [int](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction Stop).HwSchMode }
    catch { return $null }
}

function Get-VolumeSerial ([string]$Root) {
    try {
        $q = [IO.Path]::GetPathRoot($Root).TrimEnd('\')
        "$((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$q'" -ErrorAction Stop).VolumeSerialNumber)"
    } catch { '' }
}

# --- the install record ----------------------------------------------------
# $Inst = an install from Select-GammaInstall. Paths in the record stay logical
# ("Anomaly\bin\...", "GAMMA\mods\..."); Resolve-Rel maps them to the real folders.
function Open-SlopRay ($Inst, [string]$Catalogue) {
    # a game on a drive root arrives as "C:", which .NET reads as "the current directory
    # on C:" (the pack folder, or System32 when elevated). Get-NormPath keeps it a root.
    $r = Get-NormPath $Inst.Home
    $ctx = @{
        Root = $r; Anomaly = (Get-NormPath $Inst.Anomaly); Mo2 = (Get-NormPath $Inst.Mo2); Split = [bool]$Inst.Split
        Dir = "$r\.slopray"; Record = $null; WasNew = $true; Run = $null
        Cat = New-Object 'System.Collections.Generic.HashSet[string]'
        ModNames = @{}; Safe = @{}
        Notes = New-Object System.Collections.Generic.List[string]
    }
    if ($Catalogue -and (Test-Path -LiteralPath $Catalogue)) {
        $c = Get-Content -LiteralPath $Catalogue -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $c.hashes.PSObject.Properties) { [void]$ctx.Cat.Add($p.Name) }
        foreach ($n in @($c.modNames)) { $ctx.ModNames[$n] = $true }
    }
    $rp = "$($ctx.Dir)\record.json"
    if (Test-Path -LiteralPath $rp) {
        $rec = ConvertTo-Hash (Get-Content -LiteralPath $rp -Raw -Encoding UTF8 | ConvertFrom-Json)
        # a record copied over from another GAMMA folder must never be trusted
        $serial = Get-VolumeSerial $r
        if ($rec.root -ne $r -or ($rec.volumeSerial -and $serial -and $rec.volumeSerial -ne $serial) -or
            ($rec.mo2 -and $rec.mo2 -ne $ctx.Mo2) -or ($rec.anomaly -and $rec.anomaly -ne $ctx.Anomaly)) {
            throw "the Slop-Ray record in '$($ctx.Dir)' was made for '$($rec.root)'$(if ($rec.mo2) { " (MO2 folder '$($rec.mo2)')" }), not this install. " +
                  "It was probably copied with the game. Nothing was changed. Move the .slopray folder out of the way only if you are sure, then run again."
        }
        # records from v0.6 knew only the root (always the standard layout)
        if (-not $rec.anomaly) { $rec.anomaly = $ctx.Anomaly; $rec.mo2 = $ctx.Mo2 }
        foreach ($k in 'files', 'keys', 'modlist') { if (-not $rec[$k]) { $rec[$k] = @{} } }
        foreach ($k in 'dirs', 'history') { if (-not $rec[$k]) { $rec[$k] = @() } }
        if (-not $rec.shaderCache) { $rec.shaderCache = @{ baseline = $null; stale = $null } }
        $ctx.Record = $rec
        $ctx.WasNew = $false
    }
    return $ctx
}

function New-Record ($ctx) {
    @{
        schema = 1; installId = [guid]::NewGuid().ToString(); root = $ctx.Root; anomaly = $ctx.Anomaly; mo2 = $ctx.Mo2
        volumeSerial = (Get-VolumeSerial $ctx.Root); state = 'new'; runId = ''
        history = @(); files = @{}; dirs = @(); keys = @{}; modlist = @{}
        exe = $null; legacy3dss = $null; shaderCache = @{ baseline = $null; stale = $null }
    }
}

function Save-Record ($ctx) {
    Write-FileAtomic "$($ctx.Dir)\record.json" ($ctx.Record | ConvertTo-Json -Depth 8)
}

# --- paths -----------------------------------------------------------------
# rel = a logical path: "Anomaly\..." (the Anomaly folder), "GAMMA\..." (the MO2
# folder), anything else under the Home folder (.slopray, the uninstaller .bat).
# In the standard layout all three are one folder tree. Refuses anything that
# could land outside: rooted paths, "..", and links / junctions below the base.
function Resolve-Rel ($ctx, [string]$Rel) {
    $Rel = "$Rel".Replace('/', '\').Trim('\')
    if (-not $Rel -or [IO.Path]::IsPathRooted($Rel) -or $Rel.Contains(':')) { throw "unsafe path '$Rel'" }
    foreach ($seg in $Rel.Split('\')) { if ($seg -eq '' -or $seg -eq '.' -or $seg -eq '..') { throw "unsafe path '$Rel'" } }
    $base = $ctx.Root; $sub = $Rel
    if ($ctx.Split) {
        $first, $rest = $Rel.Split('\', 2)
        if ($first -ieq 'Anomaly') { $base = $ctx.Anomaly; $sub = $rest }
        elseif ($first -ieq 'GAMMA') { $base = $ctx.Mo2; $sub = $rest }
        if (-not $sub) { return $base }
    }
    $full = [IO.Path]::GetFullPath("$base\$sub")
    if (-not $full.StartsWith("$base\", [StringComparison]::OrdinalIgnoreCase)) { throw "path leaves the game folder: '$Rel'" }
    $p = $base
    foreach ($seg in $sub.Split('\')) {
        $p = "$p\$seg"
        if ($ctx.Safe.ContainsKey($p)) { continue }
        if (-not (Test-Path -LiteralPath $p)) { break }
        if ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) {
            throw "'$p' is a link or junction - not following it"
        }
        if (Test-Path -LiteralPath $p -PathType Container) { $ctx.Safe[$p] = $true }
    }
    return $full
}

# the logical path of a real path (inverse of Resolve-Rel)
function Get-Rel ($ctx, [string]$Full) {
    if ($ctx.Split) {
        foreach ($pair in @(@($ctx.Mo2, 'GAMMA'), @($ctx.Anomaly, 'Anomaly'))) {
            if ($Full -ieq $pair[0]) { return $pair[1] }
            if ($Full.StartsWith("$($pair[0])\", [StringComparison]::OrdinalIgnoreCase)) {
                $sub = $Full.Substring($pair[0].Length + 1)
                if ($pair[1] -eq 'Anomaly' -and $pair[0] -ieq $ctx.Root -and ($sub -ieq '.slopray' -or $sub -like '.slopray\*')) { return $sub }
                return "$($pair[1])\$sub"
            }
        }
    }
    $Full.Substring($ctx.Root.Length).TrimStart('\')
}

# --- runs and the journal --------------------------------------------------
function Add-Journal ($ctx, [hashtable]$Op) {
    [IO.File]::AppendAllText("$($ctx.Run.Dir)\journal.jsonl", ($Op | ConvertTo-Json -Compress -Depth 4) + "`n", $Utf8)
}

function Test-Hook ($ctx) {
    $ctx.Run.Ops++
    if ($env:SLOPRAY_TEST_KILL_AFTER -and $ctx.Run.Ops -gt [int]$env:SLOPRAY_TEST_KILL_AFTER) { [Environment]::Exit(3) }
    if ($env:SLOPRAY_TEST_FAIL_AFTER -and $ctx.Run.Ops -gt [int]$env:SLOPRAY_TEST_FAIL_AFTER) { throw "test failure injected" }
}

function Start-Run ($ctx, [string]$Kind, [string]$Version) {
    if (-not $ctx.Record) { $ctx.Record = New-Record $ctx }
    [void][IO.Directory]::CreateDirectory($ctx.Dir)
    [void](Resolve-Rel $ctx '.slopray')      # refuses a .slopray that is a junction
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Kind
    $dir = "$($ctx.Dir)\runs\$id"
    [void][IO.Directory]::CreateDirectory($dir)
    if (Test-Path -LiteralPath "$($ctx.Dir)\record.json") {
        [IO.File]::Copy("$($ctx.Dir)\record.json", "$dir\record.before.json")
    }
    $ctx.Run = @{ Id = $id; Dir = $dir; Kind = $Kind; Version = $Version; Ops = 0; Placed = @{} }
    $ctx.Record.state = $(if ($Kind -eq 'install') { 'installing' } else { 'uninstalling' })
    $ctx.Record.runId = $id
    Save-Record $ctx
}

function Move-Logged ($ctx, [string]$From, [string]$To, [string]$Kind, [string]$Hash) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $To))
    Add-Journal $ctx @{ op = 'move'; from = $From; to = $To; kind = $Kind; hash = $Hash }
    [IO.File]::Move($From, $To)          # fails if $To exists: nothing is ever overwritten
}

function Move-DirLogged ($ctx, [string]$From, [string]$To) {
    if ([IO.Path]::GetPathRoot($From) -ne [IO.Path]::GetPathRoot($To)) { throw "can't move a folder to another drive: '$From' -> '$To'" }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $To))
    Add-Journal $ctx @{ op = 'dirmove'; from = $From; to = $To }
    [IO.Directory]::Move($From, $To)
}

function New-TrackedDirs ($ctx, [string]$RelDir) {
    if (-not $RelDir) { return }                  # a file straight in the Home folder
    $r = ''
    foreach ($seg in $RelDir.Split('\')) {
        $r = $(if ($r) { "$r\$seg" } else { $seg })
        $p = Resolve-Rel $ctx $r
        if (-not (Test-Path -LiteralPath $p)) {
            Add-Journal $ctx @{ op = 'mkdir'; rel = $r }
            [void][IO.Directory]::CreateDirectory($p)
            if ($ctx.Record.dirs -notcontains $r) { $ctx.Record.dirs += $r }
        }
    }
}

function Get-BackupPath ($ctx, [string]$Rel)   { "$($ctx.Dir)\backup\$Rel" }
function Get-RecoveryPath ($ctx, [string]$Rel) { "$($ctx.Dir)\recovery\$($ctx.Run.Id)\$Rel" }
function Get-DisplacedPath ($ctx, [string]$Rel){ "$($ctx.Run.Dir)\displaced\$Rel" }

function Test-Ours ($ctx, [string]$Rel, [string]$Hash) {
    $e = $(if ($ctx.Record) { $ctx.Record.files[$Rel] } else { $null })
    ($e -and $e.installedHash -eq $Hash) -or $ctx.Cat.Contains($Hash)
}

# --- placing one file ------------------------------------------------------
# Puts $Src at $Rel. Returns 'same', 'new', 'replaced' (yours, now backed up),
# 'updated' (an older file of ours) or 'drift' (changed after we wrote it,
# moved to the recovery folder first). -PackMod: the path is inside one of our
# own MO2 mod folders, where a file proven ours by the catalogue may be removed.
function Install-OwnedFile ($ctx, [string]$Rel, [string]$Src, [switch]$PackMod, [switch]$Keep) {
    Test-Hook $ctx
    $dst = Resolve-Rel $ctx $Rel
    $new = Get-Sha $Src
    $e = $ctx.Record.files[$Rel]
    $action = 'new'
    $ctx.Run.Placed[$Rel] = $true      # the final check covers exactly these
    if (Test-Path -LiteralPath $dst -PathType Container) { throw "'$Rel' is a folder, expected a file" }
    if (Test-Path -LiteralPath $dst -PathType Leaf) {
        $cur = Get-Sha $dst
        if (-not $e) {
            $e = @{ baseline = 'present'; baselineHash = $cur; installedHash = $null }
            $ctx.Record.files[$Rel] = $e
            $old = "$dst.old"      # left by the pre-record installers: the real original
            $oldOk = (Test-Path -LiteralPath $old -PathType Leaf) -and -not $ctx.Cat.Contains((Get-Sha $old))
            if ($ctx.Cat.Contains($cur) -and $PackMod) {
                $e.baseline = 'absent'; $e.baselineHash = $null
                if ($cur -ne $new) { Move-Logged $ctx $dst (Get-DisplacedPath $ctx $Rel) 'displace' $cur }
            } elseif ($ctx.Cat.Contains($cur)) {
                # an older Slop-Ray file with no record (Adoption)
                if ($oldOk) {
                    $e.baselineHash = Get-Sha $old
                    Move-Logged $ctx $old (Get-BackupPath $ctx $Rel) 'backup' $e.baselineHash
                    if ($cur -ne $new) { Move-Logged $ctx $dst (Get-DisplacedPath $ctx $Rel) 'displace' $cur }
                } else {
                    # GAMMA may ship this exact file too: keep it, never delete it
                    $e.baseline = 'unknown'; $e.baselineHash = $cur
                    if ($cur -ne $new) { Move-Logged $ctx $dst (Get-BackupPath $ctx $Rel) 'backup' $cur }
                }
            } elseif ($cur -ne $new) {
                Move-Logged $ctx $dst (Get-BackupPath $ctx $Rel) 'backup' $cur
                $action = 'replaced'
            }
            if ($cur -eq $new) { $e.installedHash = $new; return 'same' }
            if ($action -ne 'replaced') { $action = 'updated' }
        } else {
            if ($cur -eq $new) { $e.installedHash = $new; return 'same' }
            if ($e.installedHash -and $cur -eq $e.installedHash) {
                Move-Logged $ctx $dst (Get-DisplacedPath $ctx $Rel) 'displace' $cur
                $action = 'updated'
            } elseif ($e.baseline -ne 'absent' -and $cur -eq $e.baselineHash) {
                # back to the original (after an uninstall, or put back by hand)
                $bak = Get-BackupPath $ctx $Rel
                if ((Test-Path -LiteralPath $bak) -and (Get-Sha $bak) -eq $cur) {
                    Move-Logged $ctx $dst (Get-DisplacedPath $ctx $Rel) 'displace' $cur
                } else {
                    if (Test-Path -LiteralPath $bak) { Move-Logged $ctx $bak (Get-RecoveryPath $ctx ".slopray-backup-was\$Rel") 'recover' (Get-Sha $bak) }
                    Move-Logged $ctx $dst $bak 'backup' $cur
                }
                $action = 'replaced'
            } elseif ($PackMod -and $ctx.Cat.Contains($cur)) {
                Move-Logged $ctx $dst (Get-DisplacedPath $ctx $Rel) 'displace' $cur
                $action = 'updated'
            } else {
                Move-Logged $ctx $dst (Get-RecoveryPath $ctx $Rel) 'recover' $cur
                $ctx.Notes.Add("changed by you, moved to the recovery folder: $Rel")
                $action = 'drift'
            }
        }
    } else {
        if (-not $e) {
            $e = @{ baseline = 'absent'; baselineHash = $null; installedHash = $null }
            $ctx.Record.files[$Rel] = $e
        }
    }
    New-TrackedDirs $ctx (Split-Path -Parent $Rel)
    $tmp = "$dst.sr-$($ctx.Run.Id).tmp"
    Add-Journal $ctx @{ op = 'place'; rel = $Rel; hash = $new; tmp = $tmp }
    [IO.File]::Copy($Src, $tmp, $true)
    if ((Get-Sha $tmp) -ne $new) { throw "copy check failed for $Rel (disk full or antivirus?)" }
    [IO.File]::Move($tmp, $dst)
    $e.installedHash = $new
    if ($Keep) { $e.keep = $true }
    return $action
}

# --- moving a file of yours out of the way ------------------------------------
# Moves a file that is not ours into the backup and puts nothing in its place
# (SSS24's loose Streamline DLLs). installedHash 'absent' = we removed it, so the
# uninstaller (Restore-OwnedFile) puts the backup back. Returns 'moved', 'done'
# (not there) or 'kept' (a backup of a different file is already there: left as is).
function Remove-ForeignFile ($ctx, [string]$Rel) {
    $p = Resolve-Rel $ctx $Rel
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return 'done' }
    Test-Hook $ctx
    $cur = Get-Sha $p
    $e = $ctx.Record.files[$Rel]
    if ($e -and $e.baseline -ne 'present') { return 'kept' }
    $bak = Get-BackupPath $ctx $Rel
    if (Test-Path -LiteralPath $bak) {
        if ((Get-Sha $bak) -ne $cur) { return 'kept' }
        Move-Logged $ctx $p (Get-DisplacedPath $ctx $Rel) 'displace' $cur    # backup already holds it
    } else {
        Move-Logged $ctx $p $bak 'backup' $cur
    }
    if (-not $e) { $e = @{}; $ctx.Record.files[$Rel] = $e }
    $e.baseline = 'present'; $e.baselineHash = $cur; $e.installedHash = 'absent'
    return 'moved'
}

# --- removing our files from a folder ---------------------------------------
# Removes files we can prove are ours (record, or catalogue inside our own mod
# folders). Files we can't prove: -UnknownToRecovery moves them to the recovery
# folder, otherwise they stay. -Except: rel paths to leave alone. Then removes
# folders that ended up empty. Returns $true when the folder is gone.
function Remove-OwnedTree ($ctx, [string]$RelDir, [switch]$UnknownToRecovery, [switch]$RemoveTop, $Except = @{}) {
    $full = Resolve-Rel $ctx $RelDir
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $true }
    foreach ($f in @(Get-ChildItem -LiteralPath $full -Recurse -File -Force)) {
        $rel = Get-Rel $ctx $f.FullName
        if ($Except.ContainsKey($rel)) { continue }
        Test-Hook $ctx
        $p = Resolve-Rel $ctx $rel
        $cur = Get-Sha $p
        $e = $ctx.Record.files[$rel]
        if ($e -and $e.baseline -eq 'present') { continue }      # yours from before: stays
        if (($e -and $e.installedHash -eq $cur) -or $ctx.Cat.Contains($cur)) {
            Move-Logged $ctx $p (Get-DisplacedPath $ctx $rel) 'displace' $cur
            if ($e) { $e.installedHash = $null }
        } elseif ($UnknownToRecovery) {
            Move-Logged $ctx $p (Get-RecoveryPath $ctx $rel) 'recover' $cur
            $ctx.Notes.Add("not ours or changed, moved to the recovery folder: $rel")
            if ($e) { $e.installedHash = $null }
        }
    }
    Remove-EmptyDirs $ctx $full -IncludeTop:$RemoveTop
    return -not (Test-Path -LiteralPath $full)
}

# deletes only EMPTY folders (never a folder with anything in it), deepest first
function Remove-EmptyDirs ($ctx, [string]$Top, [switch]$IncludeTop) {
    if (-not (Test-Path -LiteralPath $Top -PathType Container)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $Top -Recurse -Directory -Force |
              Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
              Sort-Object { $_.FullName.Length } -Descending)
    if ($IncludeTop) { $dirs += Get-Item -LiteralPath $Top -Force }
    foreach ($d in $dirs) {
        if (-not (Get-ChildItem -LiteralPath $d.FullName -Force | Select-Object -First 1)) {
            if ($ctx -and $ctx.Run) {
                $rel = Get-Rel $ctx $d.FullName
                if (-not $rel.StartsWith('.slopray', [StringComparison]::OrdinalIgnoreCase)) {
                    Add-Journal $ctx @{ op = 'rmdir'; rel = $rel }
                }
            }
            [IO.Directory]::Delete($d.FullName)
        }
    }
}

# --- settings files (modlist.txt, ModOrganizer.ini, user.ltx) ----------------
function Set-TextFile ($ctx, [string]$Rel, [string]$Text) {
    Test-Hook $ctx
    $dst = Resolve-Rel $ctx $Rel
    $before = ''
    if (Test-Path -LiteralPath $dst) {
        $before = "$($ctx.Run.Dir)\before\$Rel"
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $before))
        [IO.File]::Copy($dst, $before, $true)
    }
    Add-Journal $ctx @{ op = 'text'; rel = $Rel; before = $before; after = (Get-ShaText $Text) }
    $tmp = "$dst.sr-$($ctx.Run.Id).tmp"
    [IO.File]::WriteAllText($tmp, $Text, $Utf8)
    if (Test-Path -LiteralPath $dst) { [IO.File]::Replace($tmp, $dst, [NullString]::Value) } else { [IO.File]::Move($tmp, $dst) }
}

# --- finishing and undoing a run ---------------------------------------------
function Complete-Run ($ctx, [string]$State, $Extra = @{}) {
    $ctx.Record.state = $State
    $ctx.Record.runId = ''
    $h = @{ run = $ctx.Run.Id; kind = $ctx.Run.Kind; version = $ctx.Run.Version; finished = (Get-Date -Format s) }
    foreach ($k in $Extra.Keys) { $h[$k] = $Extra[$k] }
    $ctx.Record.history += $h
    Save-Record $ctx
    Add-Journal $ctx @{ op = 'commit' }
    # files we replaced with a newer copy of our own: only now are they deleted,
    # and only if they are still byte-for-byte what we moved there
    foreach ($op in (Read-Journal "$($ctx.Run.Dir)\journal.jsonl")) {
        if ($op.op -eq 'move' -and $op.kind -eq 'displace' -and (Test-Path -LiteralPath $op.to)) {
            if ((Get-Sha $op.to) -eq $op.hash) { [IO.File]::Delete($op.to) }
        }
    }
    Remove-EmptyDirs $null "$($ctx.Run.Dir)\displaced" -IncludeTop
}

function Read-Journal ([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @([IO.File]::ReadAllLines($Path, $Utf8) | Where-Object { $_.Trim() } | ForEach-Object {
        try { ConvertTo-Hash ($_ | ConvertFrom-Json) } catch { $null }   # a half-written last line
    } | Where-Object { $_ })
}

# Undo an install run that did not finish, newest operation first. Never
# deletes a file unless it is byte-for-byte what this run wrote.
function Undo-Run ($ctx, [string]$RunId) {
    $dir = "$($ctx.Dir)\runs\$RunId"
    $ops = Read-Journal "$dir\journal.jsonl"
    $problems = New-Object System.Collections.Generic.List[string]
    for ($i = $ops.Count - 1; $i -ge 0; $i--) {
        $op = $ops[$i]
        try {
            switch ($op.op) {
                'place' {
                    if (Test-Path -LiteralPath $op.tmp) { [IO.File]::Delete($op.tmp) }
                    $p = Resolve-Rel $ctx $op.rel
                    if (Test-Path -LiteralPath $p) {
                        if ((Get-Sha $p) -eq $op.hash) { [IO.File]::Delete($p) }
                        else { $problems.Add("left in place (changed during the run): $($op.rel)") }
                    }
                }
                'move' {
                    if ((Test-Path -LiteralPath $op.to) -and -not (Test-Path -LiteralPath $op.from)) {
                        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $op.from))
                        [IO.File]::Move($op.to, $op.from)
                    }
                }
                'dirmove' {
                    if ((Test-Path -LiteralPath $op.to) -and -not (Test-Path -LiteralPath $op.from)) {
                        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $op.from))
                        [IO.Directory]::Move($op.to, $op.from)
                    }
                }
                'mkdir' {
                    $p = Resolve-Rel $ctx $op.rel
                    if ((Test-Path -LiteralPath $p) -and -not (Get-ChildItem -LiteralPath $p -Force | Select-Object -First 1)) {
                        [IO.Directory]::Delete($p)
                    }
                }
                'rmdir' { [void][IO.Directory]::CreateDirectory((Resolve-Rel $ctx $op.rel)) }
                'text' {
                    $p = Resolve-Rel $ctx $op.rel
                    $tmp = "$p.sr-$RunId.tmp"
                    if (Test-Path -LiteralPath $tmp) { [IO.File]::Delete($tmp) }
                    if ((Test-Path -LiteralPath $p) -and (Get-Sha $p) -eq $op.after) {
                        if ($op.before) { [IO.File]::Copy($op.before, $p, $true) } else { [IO.File]::Delete($p) }
                    } elseif ((Test-Path -LiteralPath $p) -and $op.before -and (Get-Sha $p) -ne (Get-Sha $op.before)) {
                        $problems.Add("left as is (changed during the run): $($op.rel); the earlier copy is $($op.before)")
                    }
                }
            }
        } catch { $problems.Add("could not undo $($op.op) $($op.rel)$($op.from): $($_.Exception.Message)") }
    }
    # put the record back the way it was before the run
    if (Test-Path -LiteralPath "$dir\record.before.json") {
        [IO.File]::Copy("$dir\record.before.json", "$($ctx.Dir)\record.json", $true)
        $ctx.Record = ConvertTo-Hash (Get-Content -LiteralPath "$($ctx.Dir)\record.json" -Raw -Encoding UTF8 | ConvertFrom-Json)
    } elseif (Test-Path -LiteralPath "$($ctx.Dir)\record.json") {
        [IO.File]::Delete("$($ctx.Dir)\record.json")
        $ctx.Record = $null
    }
    Remove-EmptyDirs $null "$($ctx.Dir)\backup"
    Remove-EmptyDirs $null "$($ctx.Dir)\recovery"
    [IO.File]::WriteAllText("$dir\UNDONE.txt", "undone $(Get-Date -Format s)`r`n" + ($problems -join "`r`n"), $Utf8)
    return , $problems
}

# --- uninstall: one file -----------------------------------------------------
# Returns one of:
#   done        already the original (or already gone)
#   A restored  your original put back (file had not changed since install)
#   B kept      you changed it after install: left as is, original stays in backup
#   C removed   a file we added, unchanged: removed
#   D recovered a file we added, changed since: moved to the recovery folder
#   E kept      original backup missing or damaged: left as is
#   U kept      we never had your original (older pack, no .old): left as is
function Restore-OwnedFile ($ctx, [string]$Rel, [switch]$Plan) {
    $e = $ctx.Record.files[$Rel]
    if (-not $e -or -not $e.installedHash -or $e.keep) { return 'done' }
    $p = Resolve-Rel $ctx $Rel
    $exists = Test-Path -LiteralPath $p -PathType Leaf
    $cur = $(if ($exists) { Get-Sha $p } else { $null })
    if ($e.baseline -eq 'present') {
        if ($cur -eq $e.baselineHash) { if (-not $Plan) { $e.installedHash = $null }; return 'done' }
        if ($exists -and $cur -ne $e.installedHash) { return 'B kept' }
        $bak = Get-BackupPath $ctx $Rel
        if (-not (Test-Path -LiteralPath $bak -PathType Leaf) -or (Get-Sha $bak) -ne $e.baselineHash) { return 'E kept' }
        if ($Plan) { return 'A restored' }
        Test-Hook $ctx
        $tmp = "$p.sr-restore.tmp"
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
        [IO.File]::Copy($bak, $tmp, $true)         # the backup itself stays where it is
        if ((Get-Sha $tmp) -ne $e.baselineHash) { [IO.File]::Delete($tmp); return 'E kept' }
        if ($exists) { [IO.File]::Delete($p) }
        [IO.File]::Move($tmp, $p)
        $e.installedHash = $null
        return 'A restored'
    }
    if ($e.baseline -eq 'absent') {
        if (-not $exists) { if (-not $Plan) { $e.installedHash = $null }; return 'done' }
        if ($cur -eq $e.installedHash) {
            if ($Plan) { return 'C removed' }
            Test-Hook $ctx
            [IO.File]::Delete($p); $e.installedHash = $null
            return 'C removed'
        }
        if ($Plan) { return 'D recovered' }
        Test-Hook $ctx
        $to = Get-RecoveryPath $ctx $Rel
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to))
        [IO.File]::Move($p, $to); $e.installedHash = $null
        return 'D recovered'
    }
    return 'U kept'
}

# --- small text helpers for the settings files ------------------------------
function Get-ModlistState ([string[]]$Lines) {
    $s = @{}
    foreach ($l in $Lines) { if ($l.Length -ge 2 -and ($l[0] -eq '+' -or $l[0] -eq '-')) { $s[$l.Substring(1)] = "$($l[0])" } }
    return $s
}

Export-ModuleMember -Function * -Variable Utf8
