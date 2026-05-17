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

$json = '{"enabled":true}'
$parsed = $json | ConvertFrom-Json
$h = ConvertTo-Hashtable $parsed
Write-Host "parsed type: $($parsed.GetType().Name)"
Write-Host "is PSCustomObject? $($parsed -is [PSCustomObject])"
Write-Host "is IEnumerable? $($parsed -is [System.Collections.IEnumerable])"
Write-Host "h type: $(if ($null -eq $h) { 'null' } else { $h.GetType().Name })"
