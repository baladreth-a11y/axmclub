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
function Show-LogTail([string]$path) {
    if (Test-Path $path) {
        Info ("Last lines from " + $path + ":")
        Get-Content -LiteralPath $path -Tail 40 | ForEach-Object { Write-Host ("      " + $_) -ForegroundColor DarkGray }
    } else {
        Info ("Log not found: " + $path)
    }
}

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell (Run as Administrator).'
    }
}

function Update-CaddyfileConfig {
    param(
        [string]$InstallPath,
        [string]$CaddyRoot = 'C:\Caddy',
        [int]$Port = 8080
    )
    $liveCaddy = Join-Path $CaddyRoot 'Caddyfile'
    $backupCaddy = Join-Path $CaddyRoot 'Caddyfile.live'
    
    $domainLine = ''
    $searchFiles = @($liveCaddy, $backupCaddy)
    foreach ($file in $searchFiles) {
        if (Test-Path $file) {
            $content = Get-Content -Raw -Path $file
            $lines = $content -split "`r?`n"
            $caddyKeywords = @('servers','global','tls','log','encode','header','handle','route','respond','redir','rewrite','file_server','reverse_proxy','rate_limit','acme_dns','acme_ca','email','admin')
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                # Must end with '{', must contain a dot (real hostname), must not be a Caddy block keyword
                if ($trimmed -match '^[a-zA-Z0-9][a-zA-Z0-9\.\-,\s]+\s*\{$') {
                    $candidate = $trimmed.Replace('{', '').Trim()
                    $firstToken = ($candidate -split '[,\s]+')[0]
                    if ($firstToken -match '\.' -and $firstToken -notin $caddyKeywords) {
                        $domainLine = $candidate
                        break
                    }
                }
            }
        }
        if ($domainLine) { break }
    }
    
    if (-not $domainLine) {
        $domainLine = 'example.com, www.example.com'
    }
    
    $caddyTemplate = Get-Content -Raw -Path (Join-Path $InstallPath 'deploy\Caddyfile')
    $caddyConfig   = $caddyTemplate `
        -replace 'example\.com, www\.example\.com',   $domainLine `
        -replace '127\.0\.0\.1:8080',                 ('127.0.0.1:' + $Port) `
        -replace 'C:/apps/axmclub/uploads',           (Join-Path $InstallPath 'uploads').Replace('\', '/')
        
    Set-Content -Path $liveCaddy -Value $caddyConfig -Encoding UTF8
    Write-Host "    [Caddy] Synced uploads path in $liveCaddy with actual path: $((Join-Path $InstallPath 'uploads').Replace('\', '/'))" -ForegroundColor Green
    
    if (Test-Path $backupCaddy) {
        Set-Content -Path $backupCaddy -Value $caddyConfig -Encoding UTF8
        Write-Host "    [Caddy] Synced uploads path in $backupCaddy" -ForegroundColor Green
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
$status = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $status = (Get-Service -Name $ServiceName).Status
    if ($status -eq 'Running') { break }
    Info ("Waiting for service '$ServiceName'... status=" + $status)
}
if ($status -ne 'Running') {
    Show-LogTail (Join-Path $InstallPath 'logs\server.err.log')
    Show-LogTail (Join-Path $InstallPath 'logs\server.out.log')
    throw "Service '$ServiceName' did not reach Running state (status=$status). Check $InstallPath\logs\server.err.log"
}
Ok ("Service '$ServiceName' is " + $status + ".")

if (Get-Service -Name 'caddy' -ErrorAction SilentlyContinue) {
    Step '3b. Sync and reload Caddy'
    Update-CaddyfileConfig -InstallPath $InstallPath -Port $Port
    Restart-Service -Name 'caddy' -Force
    Start-Sleep -Seconds 2
    Ok ("Service 'caddy' is " + (Get-Service caddy).Status + ".")
} else {
    Step '3b. Skip Caddy (service not found)'
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
