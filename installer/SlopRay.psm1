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
# Join-Path THROWS on a drive letter that does not exist; build plain strings
# and wrap the test so a missing D: is just "false".
function Test-GammaRoot ($root) {
    if ([string]::IsNullOrWhiteSpace($root)) { return $false }
    try {
        $r = $root.Trim().TrimEnd('\')
        (Test-Path -LiteralPath "$r\Anomaly\bin\AnomalyDX11AVX.exe") -and
        (Test-Path -LiteralPath "$r\Anomaly\db")
    } catch { $false }
}
# accept the root, the Anomaly folder or the GAMMA folder
function Resolve-GammaRoot ($typed) {
    if ([string]::IsNullOrWhiteSpace($typed)) { return $null }
    $t = $typed.Trim().Trim('"').Trim().TrimEnd('\')
    foreach ($try in @($t, (Split-Path -Parent $t))) {
        if (Test-GammaRoot $try) { return $try }
    }
    return $null
}
# returns the GAMMA root, or throws. $From = the folder this script runs from.
function Find-GammaRoot ([string]$GamePath, [string]$From) {
    if ($GamePath) {
        # an explicit path is never second-guessed: a typo must not land in another install
        $r = Resolve-GammaRoot $GamePath
        if (-not $r) { throw "-GamePath '$GamePath' has no Anomaly\bin\AnomalyDX11AVX.exe" }
        return $r
    }
    $candidates = @($From, (Split-Path -Parent $From), (Split-Path -Parent (Split-Path -Parent $From)))
    $drives = @()
    try {
        $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                  Where-Object { $_.Root -match '^[A-Za-z]:\\$' } |
                  ForEach-Object { $_.Root.TrimEnd('\') }
    } catch { }
    if (-not $drives) { $drives = @($env:SystemDrive) }
    foreach ($d in $drives) {
        $candidates += "$d\Program Files (x86)\GOG Galaxy\Games\S.T.A.L.K.E.R. GAMMA"
        $candidates += "$d\Program Files\GOG Galaxy\Games\S.T.A.L.K.E.R. GAMMA"
        $candidates += "$d\GOG Galaxy\Games\S.T.A.L.K.E.R. GAMMA"
        $candidates += "$d\Program Files (x86)\Steam\steamapps\common\S.T.A.L.K.E.R. GAMMA"
        $candidates += "$d\SteamLibrary\steamapps\common\S.T.A.L.K.E.R. GAMMA"
        $candidates += "$d\S.T.A.L.K.E.R. GAMMA"
        $candidates += "$d\STALKER GAMMA"
        $candidates += "$d\GAMMA"
        $candidates += "$d\Games\S.T.A.L.K.E.R. GAMMA"
        $candidates += "$d\Games\STALKER GAMMA"
        $candidates += "$d\Games\GAMMA"
        $candidates += "$d\STALKER MODS\S.T.A.L.K.E.R. GAMMA"
    }
    $root = $candidates | Where-Object { Test-GammaRoot $_ } | Select-Object -First 1
    if (-not $root) {
        Write-Host "  not in the usual places - searching drives $($drives -join ' ') (a minute or two)"
        foreach ($d in $drives) {
            try {
                $hit = Get-ChildItem -LiteralPath "$d\" -Filter 'AnomalyDX11AVX.exe' -Recurse -Depth 5 `
                                     -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            } catch { $hit = $null }
            if ($hit) {
                $maybe = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $hit.FullName))
                if (Test-GammaRoot $maybe) { $root = $maybe; break }
            }
        }
    }
    while (-not $root) {
        Write-Host ""
        Write-Host "Could not find it. Open the folder that CONTAINS your 'Anomaly' folder,"
        Write-Host "copy Explorer's address bar and paste it here (right-click pastes)."
        Write-Host "Example:  G:\STALKER MODS\S.T.A.L.K.E.R. GAMMA"
        $typed = $null
        try { $typed = Read-Host "Path" } catch { throw "no folder given - run again with -GamePath" }
        $root = Resolve-GammaRoot $typed
        if (-not $root) { Write-Host "  No Anomaly\bin\AnomalyDX11AVX.exe under that folder. Try again." }
    }
    return $root
}

function Get-BusyGameProcesses {
    if ($env:SLOPRAY_TEST_NO_PROCESS_CHECK) { return @() }
    @(Get-Process -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^(Anomaly|ModOrganizer|usvfs|xrEngine)' } |
      Select-Object -Expand Name -Unique)
}

function Get-VolumeSerial ([string]$Root) {
    try {
        $q = [IO.Path]::GetPathRoot($Root).TrimEnd('\')
        "$((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$q'" -ErrorAction Stop).VolumeSerialNumber)"
    } catch { '' }
}

# --- the install record ----------------------------------------------------
function Open-SlopRay ([string]$Root, [string]$Catalogue) {
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $ctx = @{
        Root = $r; Dir = "$r\.slopray"; Record = $null; WasNew = $true; Run = $null
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
        if ($rec.root -ne $r -or ($rec.volumeSerial -and $serial -and $rec.volumeSerial -ne $serial)) {
            throw "the Slop-Ray record in '$($ctx.Dir)' was made for '$($rec.root)', not this folder. " +
                  "It was probably copied with the game. Nothing was changed. Move the .slopray folder out of the way only if you are sure, then run again."
        }
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
        schema = 1; installId = [guid]::NewGuid().ToString(); root = $ctx.Root
        volumeSerial = (Get-VolumeSerial $ctx.Root); state = 'new'; runId = ''
        history = @(); files = @{}; dirs = @(); keys = @{}; modlist = @{}
        exe = $null; legacy3dss = $null; shaderCache = @{ baseline = $null; stale = $null }
    }
}

function Save-Record ($ctx) {
    Write-FileAtomic "$($ctx.Dir)\record.json" ($ctx.Record | ConvertTo-Json -Depth 8)
}

# --- paths -----------------------------------------------------------------
# rel = path relative to the GAMMA root. Refuses anything that could land
# outside it: rooted paths, "..", and links / junctions below the root.
function Resolve-Rel ($ctx, [string]$Rel) {
    $Rel = "$Rel".Replace('/', '\').Trim('\')
    if (-not $Rel -or [IO.Path]::IsPathRooted($Rel) -or $Rel.Contains(':')) { throw "unsafe path '$Rel'" }
    foreach ($seg in $Rel.Split('\')) { if ($seg -eq '' -or $seg -eq '.' -or $seg -eq '..') { throw "unsafe path '$Rel'" } }
    $full = [IO.Path]::GetFullPath("$($ctx.Root)\$Rel")
    if (-not $full.StartsWith("$($ctx.Root)\", [StringComparison]::OrdinalIgnoreCase)) { throw "path leaves the GAMMA folder: '$Rel'" }
    $p = $ctx.Root
    foreach ($seg in $Rel.Split('\')) {
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

function Get-Rel ($ctx, [string]$Full) { $Full.Substring($ctx.Root.Length).TrimStart('\') }

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
    $ctx.Run = @{ Id = $id; Dir = $dir; Kind = $Kind; Version = $Version; Ops = 0 }
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
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $To))
    Add-Journal $ctx @{ op = 'dirmove'; from = $From; to = $To }
    [IO.Directory]::Move($From, $To)
}

function New-TrackedDirs ($ctx, [string]$RelDir) {
    $p = $ctx.Root; $r = ''
    foreach ($seg in $RelDir.Split('\')) {
        $p = "$p\$seg"; $r = $(if ($r) { "$r\$seg" } else { $seg })
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
