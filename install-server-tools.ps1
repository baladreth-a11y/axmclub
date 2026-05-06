# AxMclub.com — VPS bootstrap
#
# Purpose: bring a *fresh* Windows Server 2022 VPS from zero to serving
# https://<your-domain> in a single run. Safe to re-run — every step is
# idempotent.
#
# Run elevated (Run as Administrator) inside the VPS RDP session.
#
# Example:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   iwr https://raw.githubusercontent.com/<you>/<repo>/main/deploy/bootstrap-vps.ps1 -OutFile $env:TEMP\bootstrap.ps1
#   & $env:TEMP\bootstrap.ps1 -Domain 'axmclub.com' -RepoUrl 'https://github.com/<you>/<repo>.git'
#
# Or, if you already cloned the repo:
#   cd C:\apps\axmclub
#   .\deploy\bootstrap-vps.ps1 -Domain 'axmclub.com'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$Domain,
    [string]$RepoUrl     = '',
    [string]$InstallPath = 'C:\apps\axmclub',
    [string]$CaddyRoot   = 'C:\Caddy',
    [string]$BackupDir   = 'D:\backups\axmclub',
    [int]   $Port        = 8080,
    [string]$AdminKey    = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Step([string]$msg) { Write-Host ""; Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Info([string]$msg) { Write-Host ("    " + $msg) -ForegroundColor Gray }
function Ok  ([string]$msg) { Write-Host ("    " + $msg) -ForegroundColor Green }

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell session (Run as Administrator).'
    }
}

function Have-Command([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    return [bool]$cmd
}

function Winget-Install([string]$id, [string]$label) {
    if (Have-Command winget) {
        Info "winget install $id"
        & winget install --id $id -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
    } else {
        throw "winget is not available; install $label manually."
    }
}

Assert-Admin

Step '0. Sanity check'
Info ("Domain       : " + $Domain)
Info ("Install path : " + $InstallPath)
Info ("Caddy root   : " + $CaddyRoot)
Info ("Backup dir   : " + $BackupDir)
Info ("Port         : " + $Port)

# If -AdminKey not supplied, generate a strong one.
if (-not $AdminKey) {
    $rand    = 48..57 + 65..90 + 97..122 | Get-Random -Count 48
    $AdminKey = -join ($rand | ForEach-Object { [char]$_ })
    Info ("Generated admin key (save it!): " + $AdminKey)
}

Step '1. Install prerequisites (PowerShell 7, Git, Caddy, NSSM)'
if (-not (Have-Command pwsh))   { Winget-Install 'Microsoft.PowerShell'   'PowerShell 7' }       else { Info 'PowerShell 7 already installed.' }
if (-not (Have-Command git))    { Winget-Install 'Git.Git'                'Git'        }         else { Info 'Git already installed.' }
if (-not (Have-Command caddy))  { Winget-Install 'CaddyServer.Caddy'      'Caddy'      }         else { Info 'Caddy already installed.' }

# Chocolatey for NSSM (winget has no reliable NSSM package).
if (-not (Have-Command nssm)) {
    if (-not (Have-Command choco)) {
        Info 'Installing Chocolatey...'
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    Info 'Installing NSSM via Chocolatey...'
    & choco install nssm -y --no-progress | Out-Null
} else {
    Info 'NSSM already installed.'
}

# Refresh PATH for subsequent steps in the same session.
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
Ok 'Prerequisites ready.'

Step '2. Open firewall ports 80 + 443'
foreach ($rule in @(@{Name='HTTP';Port=80},@{Name='HTTPS';Port=443})) {
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Protocol TCP -LocalPort $rule.Port -Action Allow | Out-Null
        Info ("Added firewall rule: " + $rule.Name)
    } else {
        Info ("Firewall rule already present: " + $rule.Name)
    }
}

Step '3. Clone or update the application'
New-Item -ItemType Directory -Force -Path (Split-Path $InstallPath -Parent) | Out-Null
if (-not (Test-Path $InstallPath)) {
    if (-not $RepoUrl) { throw "InstallPath $InstallPath does not exist and -RepoUrl was not provided." }
    Info ("git clone " + $RepoUrl + " " + $InstallPath)
    & git clone $RepoUrl $InstallPath
} else {
    Info "InstallPath already exists; running git pull"
    Push-Location $InstallPath
    try { & git pull --ff-only } catch { Info "git pull skipped: $($_.Exception.Message)" }
    Pop-Location
}

Step '4. Install axmclub as a Windows service'
& (Join-Path $InstallPath 'deploy\install-service.ps1') -InstallPath $InstallPath -Port $Port -AdminKey $AdminKey

Step '5. Verify application responds on loopback'
$maxWait = 30
for ($i = 0; $i -lt $maxWait; $i++) {
    try {
        $probe = Invoke-RestMethod -Uri ("http://127.0.0.1:" + $Port + "/api/stats") -TimeoutSec 2
        Ok ("App responding: members=" + $probe.members + ", spins=" + $probe.spins)
        break
    } catch {
        Start-Sleep -Seconds 1
    }
    if ($i -eq $maxWait - 1) { throw "App never became reachable on port $Port." }
}

Step '6. Stage Caddy config for the domain'
New-Item -ItemType Directory -Force -Path $CaddyRoot             | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $CaddyRoot 'logs') | Out-Null

$caddyTemplate = Get-Content -Raw -Path (Join-Path $InstallPath 'deploy\Caddyfile')
$caddyConfig   = $caddyTemplate `
    -replace 'example\.com, www\.example\.com',   ($Domain + ', www.' + $Domain) `
    -replace '127\.0\.0\.1:8080',                 ('127.0.0.1:' + $Port)

$caddyPath = Join-Path $CaddyRoot 'Caddyfile'
Set-Content -Path $caddyPath -Value $caddyConfig -Encoding UTF8
Info ("Wrote Caddyfile -> " + $caddyPath + " (domain: " + $Domain + ")")

Step '7. Install Caddy as a Windows service'
$caddyCmd = Get-Command caddy.exe -ErrorAction SilentlyContinue
$caddyExe = if ($caddyCmd) { $caddyCmd.Source } else { $null }
if (-not $caddyExe) {
    # Fallback — winget installs to WindowsApps shim; resolve explicit path.
    $caddyExe = (Get-ChildItem "$env:ProgramFiles\Caddy*","$env:LOCALAPPDATA\Microsoft\WinGet\Packages\CaddyServer.Caddy*" -Recurse -Filter 'caddy.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
if (-not $caddyExe) { throw 'caddy.exe not found on PATH or in standard install locations.' }

$nssmExe = (Get-Command nssm.exe).Source
if (Get-Service -Name 'caddy' -ErrorAction SilentlyContinue) {
    Info 'Caddy service already installed; restarting it.'
    & $nssmExe stop  caddy confirm | Out-Null
    & $nssmExe set   caddy AppParameters ("run --config `"" + $caddyPath + "`" --adapter caddyfile") | Out-Null
} else {
    & $nssmExe install caddy $caddyExe ("run --config `"" + $caddyPath + "`" --adapter caddyfile") | Out-Null
    & $nssmExe set   caddy AppDirectory $CaddyRoot                                            | Out-Null
    & $nssmExe set   caddy Start        SERVICE_AUTO_START                                    | Out-Null
    & $nssmExe set   caddy AppStdout    (Join-Path $CaddyRoot 'logs\caddy.out.log')           | Out-Null
    & $nssmExe set   caddy AppStderr    (Join-Path $CaddyRoot 'logs\caddy.err.log')           | Out-Null
    & $nssmExe set   caddy Description  'Caddy reverse proxy / auto-TLS for axmclub'          | Out-Null
}
& $nssmExe start caddy | Out-Null
Start-Sleep -Seconds 3
$caddyStatus = (Get-Service -Name caddy).Status
if ($caddyStatus -ne 'Running') { throw "Caddy service is $caddyStatus. Check $CaddyRoot\logs\caddy.err.log" }
Ok ("Caddy service running (status=" + $caddyStatus + ").")

Step '8. Schedule nightly db.json backup'
$taskName = 'AxMclub DB backup'
$backupScript = Join-Path $InstallPath 'deploy\backup-db.ps1'
$trArg = ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $backupScript + '" -InstallPath "' + $InstallPath + '" -BackupDir "' + $BackupDir + '"')
# /Create /F overwrites an existing task in place, so the previous /Delete
# step was redundant -- and on PS 7+ its non-zero exit when the task didn't
# exist yet was promoted to a terminating error, aborting the bootstrap.
# Disable native-command error promotion just for this call so a non-zero
# schtasks exit (e.g. transient ACL issue) is reported as info, not fatal.
$prevNativeErr = $PSNativeCommandUseErrorActionPreference
try {
    if ($null -ne $prevNativeErr) { $PSNativeCommandUseErrorActionPreference = $false }
    & schtasks.exe /Create /TN $taskName /SC DAILY /ST 03:30 /RL HIGHEST /RU SYSTEM /TR $trArg /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Info ("schtasks /Create returned exit code " + $LASTEXITCODE + " -- backup task may not be registered. Run it manually if so.")
    } else {
        Ok ("Scheduled nightly backup task: '" + $taskName + "' -> " + $BackupDir)
    }
} finally {
    if ($null -ne $prevNativeErr) { $PSNativeCommandUseErrorActionPreference = $prevNativeErr }
}

Step '9. Done'
Write-Host ""
Write-Host "Next steps (not automated):" -ForegroundColor Yellow
Write-Host "  1. Point DNS A records for '$Domain' and 'www.$Domain' at this VPS's public IP."
Write-Host "     In Cloudflare: keep proxy status 'DNS only' (grey cloud) until the Let's Encrypt cert is issued."
Write-Host "  2. Watch the Caddy log for certificate issuance:"
Write-Host ("       Get-Content '" + (Join-Path $CaddyRoot 'logs\caddy.out.log') + "' -Tail 40 -Wait")
Write-Host "  3. Once you see 'certificate obtained successfully', hit https://$Domain from your laptop."
Write-Host "  4. Save the admin key below in a password manager:"
Write-Host ("       " + $AdminKey) -ForegroundColor Magenta
Write-Host ""
Write-Host "Rollback (if needed):"
Write-Host "  nssm stop axmclub; nssm stop caddy; nssm remove axmclub confirm; nssm remove caddy confirm"
