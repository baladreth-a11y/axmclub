$Root = 'C:\Users\rybek\AppData\Local\Temp\aurum-e2e-162cc6c1'
$DataDir = Join-Path $Root 'data'
$DbPath  = Join-Path $DataDir 'database.sqlite'

. .\db-sqlite.ps1
Open-DbConnection

$cmd = $Script:SqliteConn.CreateCommand()
$cmd.CommandText = "SELECT * FROM users WHERE email = 'luna@example.com' LIMIT 1"
$reader = $cmd.ExecuteReader()
if ($reader.Read()) {
    $r = @{}
    for ($i=0; $i -lt $reader.FieldCount; $i++) {
        $r[$reader.GetName($i)] = $reader.GetValue($i)
    }
    
    Write-Host "Raw: $($r.aiConfig)"
    Write-Host "Raw type: $($r.aiConfig.GetType().Name)"
    
    try {
        $parsed = $r.aiConfig | ConvertFrom-Json
        Write-Host "Parsed type: $(if ($null -eq $parsed) {'null'} else {$parsed.GetType().Name})"
        Write-Host "Parsed value: $parsed"
    } catch {
        Write-Host "Error parsing: $_"
    }
}
$reader.Close()
