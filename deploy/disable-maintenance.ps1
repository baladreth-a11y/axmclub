# Disable maintenance mode on AxMclub.com.
#
# Restores the previously-live Caddyfile (saved as Caddyfile.live by
# enable-maintenance.ps1), restarts Caddy, and the site is back to normal.
#
# Usage (elevated PowerShell on the VPS):
#   .\deploy\disable-maintenance.ps1

[CmdletBinding()]
param(
    [string]$CaddyRoot = 'C:\Caddy'
)

$ErrorActionPreference = 'Stop'

$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run from an elevated PowerShell (Run as Administrator).'
}

$liveCaddy   = Join-Path $CaddyRoot 'Caddyfile'
$backupCaddy = Join-Path $CaddyRoot 'Caddyfile.live'

if (-not (Test-Path $backupCaddy)) {
    throw "No backup Caddyfile found at $backupCaddy. Maintenance mode was not enabled via enable-maintenance.ps1."
}

Copy-Item -LiteralPath $backupCaddy -Destination $liveCaddy -Force
Write-Host ("Restored live Caddyfile <- " + $backupCaddy) -ForegroundColor Cyan

Restart-Service caddy
Start-Sleep -Seconds 3
$status = (Get-Service caddy).Status
if ($status -ne 'Running') {
    throw "Caddy did not return to Running ($status). Check $CaddyRoot\logs\caddy.err.log"
}
Write-Host ""
Write-Host "Maintenance mode is OFF. Site is back online." -ForegroundColor Green
