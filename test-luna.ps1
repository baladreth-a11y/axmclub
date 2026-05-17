$Root = $PWD
$DataDir = Join-Path $PWD 'data'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory $DataDir | Out-Null }
. .\db-sqlite.ps1
Open-DbConnection
$rows = Invoke-SqlQuery 'SELECT aiConfig FROM users WHERE email=''luna@example.com'''
$conf = $rows[0].aiConfig
Write-Host "Raw JSON: $conf"
$parsed = $conf | ConvertFrom-Json
Write-Host "Parsed enabled: $($parsed.enabled) ($($parsed.enabled.GetType().Name))"
