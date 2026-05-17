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

$Root = $PWD
$DataDir = Join-Path $PWD 'data'
. .\db-sqlite.ps1
Open-DbConnection
$u = Get-User 'luna@example.com'
Write-Host "aiConfig type: $($u.aiConfig.GetType().Name)"
Write-Host "enabled: $($u.aiConfig.enabled) ($($u.aiConfig.enabled.GetType().Name))"
