# Enable maintenance mode on AxMclub.com.
#
# What it does:
#   1. Copies deploy/maintenance.html to C:\Caddy\maintenance\maintenance.html
#   2. Renders deploy/Caddyfile.maintenance with your operator IP allow-list
#      to C:\Caddy\Caddyfile (preserving the original at Caddyfile.live)
#   3. Restarts the caddy Windows service so it picks up the new config
#
# After this, the public sees the maintenance page (HTTP 503) at
# https://axmcamclub.com. IPs on the -AllowIp list get the real site
# transparently so you can keep testing.
#
# Usage (elevated PowerShell on the VPS):
#   .\deploy\enable-maintenance.ps1 -AllowIp '203.0.113.42'
#   .\deploy\enable-maintenance.ps1 -AllowIp '203.0.113.42','198.51.100.10'
#   .\deploy\enable-maintenance.ps1                     # no bypass — everyone sees the page

[CmdletBinding()]
param(
    [string[]]$AllowIp = @(),
    [string]$InstallPath = 'C:\apps\axmclub',
    [string]$CaddyRoot   = 'C:\Caddy'
)

$ErrorActionPreference = 'Stop'

# Elevation check
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run from an elevated PowerShell (Run as Administrator).'
}

$srcHtml      = Join-Path $InstallPath 'deploy\maintenance.html'
$srcCaddyTpl  = Join-Path $InstallPath 'deploy\Caddyfile.maintenance'
$liveCaddy    = Join-Path $CaddyRoot   'Caddyfile'
$backupCaddy  = Join-Path $CaddyRoot   'Caddyfile.live'
$dstHtmlDir   = Join-Path $CaddyRoot   'maintenance'
$dstHtml      = Join-Path $dstHtmlDir  'maintenance.html'

foreach ($f in @($srcHtml, $srcCaddyTpl)) {
    if (-not (Test-Path $f)) { throw "Required file not found: $f" }
}
if (-not (Test-Path $liveCaddy)) { throw "No live Caddyfile at $liveCaddy. Run the bootstrap first." }

# 1. Stage the maintenance HTML in Caddy's site root
New-Item -ItemType Directory -Force -Path $dstHtmlDir | Out-Null
Copy-Item -LiteralPath $srcHtml -Destination $dstHtml -Force
Write-Host ("Staged maintenance page -> " + $dstHtml) -ForegroundColor Cyan

# 2. Back up the live Caddyfile (keeps the most recent .live copy)
Copy-Item -LiteralPath $liveCaddy -Destination $backupCaddy -Force
Write-Host ("Backed up live Caddyfile -> " + $backupCaddy) -ForegroundColor Gray

# 3. Render the maintenance Caddyfile with the operator allow-list
$tpl = Get-Content -Raw -Path $srcCaddyTpl
if ($AllowIp.Count -eq 0) {
    # No bypass IPs => use a placeholder that matches no real client.
    $ipList = '127.0.0.2'
} else {
    $ipList = ($AllowIp | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' '
}
$rendered = $tpl -replace 'OPERATOR_IPS_PLACEHOLDER', $ipList
Set-Content -Path $liveCaddy -Value $rendered -Encoding UTF8
Write-Host ("Wrote maintenance Caddyfile -> " + $liveCaddy) -ForegroundColor Cyan
Write-Host ("Bypass allow-list: " + $ipList) -ForegroundColor Yellow

# 4. Restart Caddy
Restart-Service caddy
Start-Sleep -Seconds 3
$status = (Get-Service caddy).Status
if ($status -ne 'Running') {
    throw "Caddy did not return to Running ($status). Check $CaddyRoot\logs\caddy.err.log"
}
Write-Host ""
Write-Host "Maintenance mode is ON." -ForegroundColor Green
Write-Host ("Public sees: https://axmcamclub.com -> 503 + maintenance page")
Write-Host ("Bypass:      requests from " + $ipList + " still hit the real site")
Write-Host ""
Write-Host "Disable with:  .\deploy\disable-maintenance.ps1"
