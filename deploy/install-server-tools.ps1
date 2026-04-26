# Install operator tooling on the AxMclub.com VPS.
#
# Idempotent -- re-runs safely. Skips packages already installed.
#
# Tools installed (all free):
#   - VS Code               (file editing, JSON pretty-print, Caddyfile syntax)
#   - Notepad++             (quick edits + log tail)
#   - Sysinternals Suite    (Process Explorer, TCPView, Autoruns, Procmon)
#   - bottom (btm)          (terminal-based system monitor)
#   - AnyDesk               (faster, smoother remote desktop than UltraVNC)
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

function Try-Winget([string]$id, [string]$label, [string]$probe) {
    if ($probe -and (Have-Command $probe)) {
        Info ("$label already on PATH ($probe). Skipping.")
        return
    }
    if (-not (Have-Command winget)) {
        Info ("winget not available; install $label manually.")
        return
    }
    Info ("winget install $id ...")
    & winget install --id $id -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
    Ok ("$label install attempt complete.")
}

Step '1. VS Code'
Try-Winget 'Microsoft.VisualStudioCode' 'VS Code' 'code'

Step '2. Notepad++'
Try-Winget 'Notepad++.Notepad++' 'Notepad++' 'notepad++'

Step '3. Sysinternals Suite (Process Explorer, TCPView, Autoruns, Procmon, ...)'
Try-Winget 'Microsoft.Sysinternals' 'Sysinternals Suite' 'procexp'

Step '4. bottom (btm) — terminal system monitor'
Try-Winget 'Clement.bottom' 'bottom' 'btm'

Step '5. AnyDesk (remote desktop client/host)'
Try-Winget 'AnyDeskSoftwareGmbH.AnyDesk' 'AnyDesk' 'AnyDesk'

Step '6. jq (CLI JSON pretty-printer)'
Try-Winget 'jqlang.jq' 'jq' 'jq'

if ($IncludeRainmeter) {
    Step '7. Rainmeter (desktop widgets)'
    Try-Winget 'Rainmeter.Rainmeter' 'Rainmeter' 'Rainmeter'
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
    @{ cmd='AnyDesk';     label='AnyDesk'                     },
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
Write-Host "  * AnyDesk:               note the 9-digit AnyDesk ID shown in the app, install on dev box too, connect by ID"
Write-Host "  * CrowdSec:              skip for now; their Windows agent is still preview-grade"
Write-Host ""
Write-Host "Tip: pin Process Explorer + TCPView to the taskbar for one-click access."
