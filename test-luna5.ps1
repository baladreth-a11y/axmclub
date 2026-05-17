$Root = 'C:\Users\rybek\AppData\Local\Temp\aurum-e2e-162cc6c1'
$DataDir = Join-Path $Root 'data'
$DbPath  = Join-Path $DataDir 'database.sqlite'

function ConvertTo-Hashtable {
  param($obj)
  if ($null -eq $obj) { return $null }
  if ($obj -is [hashtable]) { return $obj }
  if ($obj -is [System.Collections.IDictionary]) {
    $h = @{}
    foreach ($k in $obj.Keys) { $h[$k] = ConvertTo-Hashtable $obj[$k] }
    return $h
  }
  if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
    return @($obj | ForEach-Object { ConvertTo-Hashtable $_ })
  }
  if ($obj -is [PSCustomObject]) {
    $h = @{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable $p.Value }
    return $h
  }
  return $obj
}

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
    
    $aiConfig = if ($r.aiConfig -is [System.DBNull]) { @{} } else { $r.aiConfig | ConvertFrom-Json | ConvertTo-Hashtable }
    Write-Host "Parsed aiConfig type: $($aiConfig.GetType().Name)"
    Write-Host "Parsed enabled: $($aiConfig.enabled)"
}
$reader.Close()
