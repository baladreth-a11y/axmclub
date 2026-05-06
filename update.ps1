# Install operator tooling on the AxMclub.com VPS.
#
# Idempotent -- re-runs safely. Skips packages already installed.
#
# Tools installed (all free):
#   - VS Code               (file editing, JSON pretty-print, Caddyfile syntax)
#   - Notepad++             (quick edits + log tail)
#   - Sysinternals Suite    (Process Explorer, TCPView, Autoruns, Procmon)
#   - bottom (btm)          (terminal-based system monitor)
#   - jq                    (CLI JSON pretty-printer for db.json)
#
# Optional with -IncludeRainmeter:
#   - Rainmeter             (desktop widgets / system monitor on the desktop)
#
# Tools NOT covered here (browser / Store needed):
#   - Files (Microsoft Store)        -> Open Microsoft Store, search "Files"
#   - Windows Admin Center           -> https://aka.ms/WACDownload (MSI, ~120 MB)
#   - UptimeRobot                    -> https://uptimerobot.com (signup + add monitors)
#   - CrowdSec (Windows is preview)  -> skip until they GA on Windows
#
# Usage (elevated PowerShell on the VPS):
#   .\deploy\install-server-tools.ps1
#   .\deploy\install-server-tools.ps1 -IncludeRainmeter

[CmdletBinding()]
param(
    [switch]$IncludeRainmeter
)

$ErrorActionPreference = 'Stop'

# Elevation guard
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run from an elevated PowerShell (Run as Administrator).'
}

function Have-Command([string]$name) {
    [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Step([string]$msg) {
    Write-Host ""; Write-Host ("==> " + $msg) -ForegroundColor Cyan
}
function Ok([string]$msg)   { Write-Host ("    " + $msg) -ForegroundColor Green }
function Info([string]$msg) { Write-Host ("    " + $msg) -ForegroundColor Gray }

# Try winget first; fall back to Chocolatey. Windows Server commonly ships
# without winget, but our bootstrap-vps.ps1 has already installed Chocolatey.
function Try-Install {
    param(
        [string]$Label,
        [string]$Probe,
        [string]$WingetId,
        [string]$ChocoId
    )
    if ($Probe -and (Have-Command $Probe)) {
        Info ("$Label already on PATH ($Probe). Skipping.")
        return
    }
    if (Have-Command winget) {
        Info ("winget install $WingetId ...")
        & winget install --id $WingetId -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
        Ok ("$Label install attempt via winget complete.")
        return
    }
    if (Have-Command choco) {
        Info ("choco install $ChocoId ...")
        & choco install $ChocoId -y --no-progress | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Ok ("$Label install attempt via choco complete.")
        } else {
            Info ("choco returned exit $LASTEXITCODE for $ChocoId; check the choco log.")
        }
        return
    }
    Info ("Neither winget nor choco available; install $Label manually.")
}

Step '1. VS Code'
Try-Install -Label 'VS Code'             -Probe 'code'      -WingetId 'Microsoft.VisualStudioCode'  -ChocoId 'vscode'

Step '2. Notepad++'
Try-Install -Label 'Notepad++'           -Probe 'notepad++' -WingetId 'Notepad++.Notepad++'         -ChocoId 'notepadplusplus'

Step '3. Sysinternals Suite (Process Explorer, TCPView, Autoruns, Procmon, ...)'
Try-Install -Label 'Sysinternals Suite'  -Probe 'procexp'   -WingetId 'Microsoft.Sysinternals'      -ChocoId 'sysinternals'

Step '4. bottom (btm) - terminal system monitor'
Try-Install -Label 'bottom'              -Probe 'btm'       -WingetId 'Clement.bottom'              -ChocoId 'bottom'

Step '5. jq (CLI JSON pretty-printer)'
Try-Install -Label 'jq'                  -Probe 'jq'        -WingetId 'jqlang.jq'                   -ChocoId 'jq'

if ($IncludeRainmeter) {
    Step '6. Rainmeter (desktop widgets)'
    Try-Install -Label 'Rainmeter'       -Probe 'Rainmeter' -WingetId 'Rainmeter.Rainmeter'         -ChocoId 'rainmeter'
} else {
    Info 'Skipping Rainmeter (pass -IncludeRainmeter to include).'
}

# Refresh PATH so freshly-installed binaries are reachable in this session
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

Step 'Versions'
foreach ($pair in @(
    @{ cmd='code';        label='VS Code'                     },
    @{ cmd='notepad++';   label='Notepad++'                   },
    @{ cmd='procexp';     label='Process Explorer (Sysinternals)' },
    @{ cmd='tcpview';     label='TCPView'                     },
    @{ cmd='btm';         label='bottom'                      },
    @{ cmd='jq';          label='jq'                          }
)) {
    if (Have-Command $pair.cmd) {
        Ok ("{0,-44} {1}" -f $pair.label, (Get-Command $pair.cmd).Source)
    } else {
        Info ("{0,-44} not on PATH (open new shell or check install)" -f $pair.label)
    }
}

Write-Host ""
Write-Host "Done. Next up (manual / browser):" -ForegroundColor Yellow
Write-Host "  * Windows Admin Center:  https://aka.ms/WACDownload  (download MSI, install, browse to https://localhost:6516)"
Write-Host "  * Files (file manager):  Open Microsoft Store on the VPS, search 'Files', Install"
Write-Host "  * UptimeRobot:           https://uptimerobot.com -> sign up -> Add Monitor (HTTPS) for axmcamclub.com"
Write-Host "  * CrowdSec:              skip for now; their Windows agent is still preview-grade"
Write-Host ""
Write-Host "Tip: pin Process Explorer + TCPView to the taskbar for one-click access."
