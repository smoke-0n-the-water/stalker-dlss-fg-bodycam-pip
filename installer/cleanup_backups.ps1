# ===========================================================================
#  Optional clean-up after a COMPLETE uninstall. PLAIN TEXT.
#
#  Deletes a backup copy only when ALL of these hold:
#    - the last uninstall finished with "COMPLETE"
#    - the backup still matches the hash recorded when it was made
#    - your original is back in place, byte-for-byte the same as the backup
#  Anything else is kept. The recovery folder is never touched.
#     -Yes   don't ask      -GamePath "..."   skip auto-detection
# ===========================================================================
[CmdletBinding()]
param([string]$GamePath, [switch]$Yes)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\SlopRay.psm1" -Force -DisableNameChecking
function Done ($code) { if (-not $Yes) { try { Read-Host "Press Enter to close" | Out-Null } catch { } }; exit $code }

try { $root = (Find-GammaRoot $GamePath $here).TrimEnd('\'); $sr = Open-SlopRay $root $null }
catch { Write-Host "  [STOP] $($_.Exception.Message)" -ForegroundColor Red; Done 1 }

$last = @($sr.Record.history | Where-Object { $_.kind -eq 'uninstall' }) | Select-Object -Last 1
if ($sr.WasNew -or $sr.Record.state -ne 'uninstalled' -or -not $last -or -not $last.complete) {
    Write-Host "  Backups are only removed after a COMPLETE uninstall. Nothing was changed." -ForegroundColor Yellow
    Done 1
}
$bdir = "$($sr.Dir)\backup"
$del = @(); $keep = 0
foreach ($f in @(Get-ChildItem -LiteralPath $bdir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($bdir.Length + 1)
    $e = $sr.Record.files[$rel]
    $h = Get-Sha $f.FullName
    $live = "$root\$rel"
    if ($e -and $e.baselineHash -eq $h -and (Test-Path -LiteralPath $live -PathType Leaf) -and (Get-Sha $live) -eq $h) { $del += $f.FullName }
    else { $keep++ }
}
Write-Host "  $($del.Count) backup copies are no longer needed (your originals are back in place)."
if ($keep) { Write-Host "  $keep backup copies are kept: they are the only copy, or don't match the record." }
if (-not $del.Count) { Done 0 }
if (-not $Yes) {
    try { $ok = (Read-Host "Delete those $($del.Count) backup copies? (Y/N)") -match '^\s*(y|yes)\s*$' } catch { $ok = $false }
    if (-not $ok) { Write-Host "  Nothing deleted."; Done 1 }
}
foreach ($p in $del) { [IO.File]::Delete($p) }
Remove-EmptyDirs $null $bdir
Write-Host "  [ok]   deleted $($del.Count) backup copies. Recovery folder untouched: $($sr.Dir)\recovery" -ForegroundColor Green
Done 0
