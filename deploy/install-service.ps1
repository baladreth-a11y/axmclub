# Install AxMclub.com as a Windows service via NSSM.
#
# Run elevated. Idempotent: re-running with different params updates the
# existing service in place.
#
# Prereqs:
#   - PowerShell 7      (winget install Microsoft.PowerShell)
#   - NSSM              (choco install nssm  OR  https://nssm.cc/download)
#
# Usage:
#   .\deploy\install-service.ps1 `
#       -InstallPath 'C:\apps\axmclub' `
#       -Port        8080 `
#       -AdminKey    '<long-random-string>'
#
# After install the service runs under LOCAL SYSTEM and auto-starts on boot.
# Data/db.json lives at <InstallPath>\data\db.json -- back that file up.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InstallPath,
    [Parameter(Mandatory=$true)][int]$Port,
    [Parameter(Mandatory=$true)][string]$AdminKey,
    [string]$ServiceName = 'axmclub',
    # If not supplied, we auto-detect pwsh on PATH or in common install roots.
    [string]$PwshPath    = ''
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell (Run as Administrator).'
    }
}

function Assert-Path($label, $path) {
    if (-not (Test-Path $path)) { throw "$label not found: $path" }
}

function Resolve-PwshPath {
    # 1. Try PATH
    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source) -and ($cmd.Source -notlike '*WindowsApps*')) {
        return $cmd.Source
    }
    # 2. Common install locations (MSI, winget, MSIX, Scoop)
    $candidates = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    # 3. Glob winget package cache
    $pkgRoot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    if (Test-Path $pkgRoot) {
        $hit = Get-ChildItem -Path $pkgRoot -Filter 'pwsh.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

Assert-Admin

# Resolve + validate paths.
$InstallPath = (Resolve-Path $InstallPath).Path
Assert-Path 'InstallPath' $InstallPath
Assert-Path 'server.ps1'  (Join-Path $InstallPath 'server.ps1')

if (-not $PwshPath) { $PwshPath = Resolve-PwshPath }
if (-not $PwshPath -or -not (Test-Path $PwshPath)) {
    throw "PowerShell 7 (pwsh.exe) not found. Install it with:  winget install --id Microsoft.PowerShell -e"
}
Write-Host ("Using pwsh: " + $PwshPath) -ForegroundColor DarkGray

# NSSM must be on PATH.
$nssmCmd = Get-Command nssm.exe -ErrorAction SilentlyContinue
$nssm    = if ($nssmCmd) { $nssmCmd.Source } else { $null }
if (-not $nssm) { throw 'nssm.exe not found on PATH. Install from https://nssm.cc/ or `choco install nssm`.' }

$serverScript = Join-Path $InstallPath 'server.ps1'
$logDir       = Join-Path $InstallPath 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$svcArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$serverScript`" -Port $Port"

# Remove any existing service with the same name so this script is idempotent.
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host "Stopping existing service '$ServiceName'..." -ForegroundColor Yellow
    & $nssm stop   $ServiceName confirm | Out-Null
    & $nssm remove $ServiceName confirm | Out-Null
}

Write-Host "Installing service '$ServiceName'..." -ForegroundColor Cyan
& $nssm install $ServiceName $PwshPath $svcArgs | Out-Null
& $nssm set $ServiceName AppDirectory          $InstallPath                                 | Out-Null
& $nssm set $ServiceName Start                 SERVICE_AUTO_START                            | Out-Null
& $nssm set $ServiceName AppStdout             (Join-Path $logDir 'server.out.log')          | Out-Null
& $nssm set $ServiceName AppStderr             (Join-Path $logDir 'server.err.log')          | Out-Null
& $nssm set $ServiceName AppRotateFiles        1                                             | Out-Null
& $nssm set $ServiceName AppRotateBytes        10485760                                      | Out-Null
& $nssm set $ServiceName AppEnvironmentExtra   "AURUM_ADMIN_KEY=$AdminKey"                   | Out-Null
& $nssm set $ServiceName Description 'AxMclub.com members site (PowerShell HttpListener)'    | Out-Null

Write-Host "Starting service..." -ForegroundColor Cyan
& $nssm start $ServiceName | Out-Null

Start-Sleep -Seconds 2
$status = (Get-Service -Name $ServiceName).Status
if ($status -ne 'Running') {
    throw "Service did not reach Running state (status=$status). Check $logDir\server.err.log"
}

Write-Host ""
Write-Host "OK - $ServiceName is running on http://127.0.0.1:$Port" -ForegroundColor Green
Write-Host "Admin key is stored in the service environment; rotate it with:"
Write-Host "    nssm set $ServiceName AppEnvironmentExtra 'AURUM_ADMIN_KEY=<new-key>'"
Write-Host "    Restart-Service $ServiceName"
