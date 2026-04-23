# Nightly backup for AxMclub.com state.
#
# Snapshots  <InstallPath>\data\db.json  to  <BackupDir>\db-<timestamp>.json,
# then rotates: keeps the newest N copies and deletes the rest.
#
# Usage (manual):
#   .\deploy\backup-db.ps1 -InstallPath 'C:\apps\axmclub' -BackupDir 'D:\backups\axmclub'
#
# Register as a scheduled task (runs every day at 03:30, as SYSTEM):
#   schtasks /Create /TN "AxMclub DB backup" /SC DAILY /ST 03:30 /RL HIGHEST /RU SYSTEM ^
#     /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\apps\axmclub\deploy\backup-db.ps1 -InstallPath C:\apps\axmclub -BackupDir D:\backups\axmclub"
#
# Tip: point -BackupDir at a separate disk OR a mounted UNC path (Azure Files /
# S3 gateway / NAS) so a single-disk failure can't take out both copies.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InstallPath,
    [Parameter(Mandatory=$true)][string]$BackupDir,
    [int]$Keep = 30
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $InstallPath 'data\db.json'
if (-not (Test-Path $src)) {
    Write-Warning "No db.json at $src - nothing to back up (server may not have started yet)."
    exit 0
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dst   = Join-Path $BackupDir "db-$stamp.json"

# Use Copy-Item — db.json is a small file, so atomic copy is simplest.
# For very large state files, swap this for:  robocopy (Split-Path $src) $BackupDir (Split-Path -Leaf $src) /COPY:DAT /R:2 /W:5
Copy-Item -LiteralPath $src -Destination $dst -Force

# Optional: emit the file size so the scheduler log has something useful.
$bytes = (Get-Item $dst).Length
Write-Host ("Backed up {0} -> {1} ({2:N0} bytes)" -f $src, $dst, $bytes)

# Rotation: keep newest N, delete older.
$old = Get-ChildItem -LiteralPath $BackupDir -Filter 'db-*.json' -File |
       Sort-Object LastWriteTime -Descending |
       Select-Object -Skip $Keep

foreach ($f in $old) {
    try {
        Remove-Item -LiteralPath $f.FullName -Force
        Write-Host ("Rotated out: {0}" -f $f.Name)
    } catch {
        Write-Warning ("Could not remove {0}: {1}" -f $f.FullName, $_.Exception.Message)
    }
}
