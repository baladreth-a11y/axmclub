# AxMclub.com — Setup SMTP
#
# Use this script to update your email settings on the VPS.
#
# Usage (elevated):
#   .\deploy\setup-smtp.ps1 `
#       -SmtpHost 'smtp.gmail.com' `
#       -SmtpPort 587 `
#       -SmtpUser 'your-email@gmail.com' `
#       -SmtpPass 'your-app-password' `
#       -PublicBaseUrl 'https://axmcamclub.com'
#

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SmtpHost,
    [int]$SmtpPort = 587,
    [Parameter(Mandatory=$true)][string]$SmtpUser,
    [Parameter(Mandatory=$true)][string]$SmtpPass,
    [string]$SmtpFrom = '',
    [string]$PublicBaseUrl = '',
    [string]$ServiceName = 'axmclub'
)

$ErrorActionPreference = 'Stop'

function Step([string]$msg) { Write-Host ""; Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Ok  ([string]$msg) { Write-Host ("    " + $msg) -ForegroundColor Green }

# 1. Verify service exists
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) { throw "Service '$ServiceName' not found. Run bootstrap-vps.ps1 first." }

# 2. Find nssm
$nssm = (Get-Command nssm.exe -ErrorAction SilentlyContinue).Source
if (-not $nssm) { throw "nssm.exe not found on PATH." }

Step "Updating environment for service '$ServiceName'..."

# Get current environment so we don't lose other variables like AURUM_ADMIN_KEY
# NSSM stores environment as a list of KEY=VALUE strings separated by nulls or newlines.
$currentEnv = & $nssm get $ServiceName AppEnvironmentExtra
$envMap = @{}
if ($currentEnv) {
    foreach ($line in ($currentEnv -split "`r`n")) {
        if ($line -match '^([^=]+)=(.*)$') {
            $envMap[$matches[1]] = $matches[2]
        }
    }
}

# Update with new values
$envMap['AURUM_SMTP_HOST'] = $SmtpHost
$envMap['AURUM_SMTP_PORT'] = [string]$SmtpPort
$envMap['AURUM_SMTP_USER'] = $SmtpUser
$envMap['AURUM_SMTP_PASS'] = $SmtpPass
if ($SmtpFrom) { $envMap['AURUM_SMTP_FROM'] = $SmtpFrom }
elseif ($SmtpUser -match '@') { $envMap['AURUM_SMTP_FROM'] = $SmtpUser }

if ($PublicBaseUrl) { $envMap['AURUM_BASE_URL'] = $PublicBaseUrl }

# Rebuild block
$newEnv = @()
foreach ($k in $envMap.Keys) {
    $newEnv += "$k=$($envMap[$k])"
}
$envBlock = $newEnv -join "`r`n"

& $nssm set $ServiceName AppEnvironmentExtra $envBlock
Ok "Environment updated."

Step "Restarting service..."
Restart-Service $ServiceName -Force
Ok "Service restarted."

Write-Host ""
Write-Host "Done! You can now test registration or verification emails." -ForegroundColor Green
