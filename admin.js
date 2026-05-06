# AxMclub.com — VPS update
#
# Pulls the latest commit on the configured branch, restarts the service,
# and smoke-tests /api/stats. Safe to re-run.
#
# Run elevated on the VPS:
#   cd C:\apps\axmclub
#   .\deploy\update.ps1
#
# Optional flags:
#   -InstallPath C:\apps\axmclub      (default)
#   -ServiceName axmclub              (default)
#   -Port        8080                 (default; matches install-service.ps1)
#   -Branch      main                 (default)
#   -RestartCaddy                     (also bounce the caddy service)

[CmdletBinding()]
param(
    [string]$InstallPath = 'C:\apps\axmclub',
    [string]$ServiceName = 'axmclub',
    [int]   $Port        = 8080,
    [string]$Branch      = 'main',
    [switch]$RestartCaddy
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Step([string]$msg) { Write-Host ''; Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Info([string]$msg) { Write-Host ("    " + $msg) -ForegroundColor Gray }
function Ok  ([string]$msg) { Write-Host ("    " + $msg) -ForegroundColor Green }

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell session (Run as Administrator).'
    }
}

Assert-Admin

if (-not (Test-Path $InstallPath)) { throw "InstallPath not found: $InstallPath" }
if (-not (Test-Path (Join-Path $InstallPath '.git'))) {
    throw "$InstallPath is not a git working tree. Re-run deploy\bootstrap-vps.ps1 to clone."
}

Step '1. Capture current revision'
Push-Location $InstallPath
try {
    $before = (& git rev-parse --short HEAD).Trim()
    Info ("Currently at: " + $before)

    Step '2. git pull'
    & git fetch --quiet origin
    & git checkout --quiet $Branch
    & git pull --ff-only origin $Branch
    $after = (& git rev-parse --short HEAD).Trim()
    if ($before -eq $after) {
        Info ("Already up to date (" + $after + ").")
    } else {
        Ok ("Updated " + $before + " -> " + $after)
        & git --no-pager log --oneline ($before + '..' + $after)
    }
} finally {
    Pop-Location
}

Step '3. Restart service'
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    throw "Service '$ServiceName' is not installed. Re-run deploy\install-service.ps1."
}
Restart-Service -Name $ServiceName -Force
Start-Sleep -Seconds 2
$status = (Get-Service -Name $ServiceName).Status
if ($status -ne 'Running') {
    throw "Service '$ServiceName' did not reach Running state (status=$status). Check $InstallPath\logs\server.err.log"
}
Ok ("Service '$ServiceName' is " + $status + ".")

if ($RestartCaddy) {
    Step '3b. Restart caddy'
    if (Get-Service -Name 'caddy' -ErrorAction SilentlyContinue) {
        Restart-Service -Name 'caddy' -Force
        Start-Sleep -Seconds 2
        Ok ("Service 'caddy' is " + (Get-Service caddy).Status + ".")
    } else {
        Info "No 'caddy' service found, skipping."
    }
}

Step '4. Smoke-test /api/stats'
$probeUrl = "http://127.0.0.1:$Port/api/stats"
$ok = $false
for ($i = 0; $i -lt 15; $i++) {
    try {
        $probe = Invoke-RestMethod -Uri $probeUrl -TimeoutSec 2
        Ok ("App responding: members=" + $probe.members + ", spins=" + $probe.spins)
        $ok = $true
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}
if (-not $ok) {
    throw "App never became reachable on $probeUrl. Check $InstallPath\logs\server.err.log"
}

Step '5. Done'
Write-Host ''
Ok 'Update complete. Open the site in a browser to spot-check.'
