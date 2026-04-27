$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestDir = Join-Path $env:TEMP ('axm-manual-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$Port    = 5176
$Base    = 'http://localhost:' + $Port

$pass = 0; $fail = 0
function Ok($n, $c, $d='')  {
  if ($c) { $script:pass++; Write-Host ("  [PASS] " + $n) -ForegroundColor Green }
  else    { $script:fail++; $s = if ($d) { " :: $d" } else { '' }; Write-Host ("  [FAIL] " + $n + $s) -ForegroundColor Red }
}
function Code($ex) { try { [int]$ex.Exception.Response.StatusCode.Value__ } catch { 0 } }

New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
Copy-Item (Join-Path $Root 'server.ps1') (Join-Path $TestDir 'server.ps1')
Copy-Item (Join-Path $Root 'styles.css') (Join-Path $TestDir 'styles.css')
Copy-Item -Recurse (Join-Path $Root 'js') (Join-Path $TestDir 'js')
Get-ChildItem -Path $Root -Filter '*.html' -File |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $TestDir $_.Name) -ErrorAction SilentlyContinue }

$sp = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $TestDir 'server.ps1'),'-Port',$Port -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $TestDir 'out.log') -RedirectStandardError (Join-Path $TestDir 'err.log')
Start-Sleep -Seconds 2

try {
  for ($i=0; $i -lt 20; $i++) {
    try { $null = Invoke-RestMethod -Uri ($Base + '/api/stats') -TimeoutSec 2; break } catch { Start-Sleep -Milliseconds 500 }
  }

  Write-Host ""
  Write-Host "== 1. Anonymous HTML gate state ==" -ForegroundColor Cyan
  $html = Invoke-WebRequest -Uri ($Base + '/') -UseBasicParsing
  Ok 'GET / returns 200'                            ($html.StatusCode -eq 200)
  Ok 'Body has is-gated class'                      ($html.Content -match 'body class="[^"]*\bis-gated\b')
  Ok 'Body also starts with is-age-gated (blur)'    ($html.Content -match 'body class="[^"]*\bis-age-gated\b')
  Ok 'Gate overlay is visible (no hidden)'          ($html.Content -match 'id="gate" class="gate"[^h]')
  Ok 'Age stage is shown first (not hidden)'        ($html.Content -match 'class="gate-card" data-stage="age"')
  Ok 'Auth stage is hidden initially'               ($html.Content -match 'class="gate-card hidden" data-stage="auth"')
  Ok 'Age gate asks 18+ question'                   ($html.Content -match 'Are you 18 or older')
  Ok 'Age gate has 18+ confirm button'              ($html.Content -match 'id="gateAgeYes"')
  Ok 'Register form has acct-segment'               ($html.Content -match 'class="acct-segment"')
  Ok 'Auth stage CTA is Create Supporter account'   ($html.Content -match 'Create Supporter account')

  Write-Host ""
  Write-Host "== 2. Anonymous /api/me is null ==" -ForegroundColor Cyan
  $me0 = Invoke-RestMethod -Uri ($Base + '/api/me')
  Ok '/api/me.user is null before login' ($null -eq $me0.user)

  Write-Host ""
  Write-Host "== 3. Register as Model is rejected ==" -ForegroundColor Cyan
  $modelCode = 0
  try {
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' `
      -Body (@{ name='Mo Del'; email='mo@example.com'; password='abcd'; accountType='model' } | ConvertTo-Json)
  } catch { $modelCode = Code $_ }
  Ok 'Model registration returns 403' ($modelCode -eq 403) ('got ' + $modelCode)

  Write-Host ""
  Write-Host "== 4. Register as Supporter succeeds ==" -ForegroundColor Cyan
  $sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $reg = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $sess `
    -Body (@{ name='Sam Support'; email='sam@example.com'; password='abcd'; accountType='supporter' } | ConvertTo-Json)
  Ok 'Register returns user'                      ($reg.user -and $reg.user.email -eq 'sam@example.com')
  Ok 'Returned accountType is supporter'          ($reg.user.accountType -eq 'supporter') ('got ' + $reg.user.accountType)
  Ok 'Session cookie was set (sid present)'       ($sess.Cookies.GetCookies($Base) | Where-Object { $_.Name -eq 'sid' } | Select-Object -First 1)
  Ok 'Initial balance is 0'                       ($reg.user.points -eq 0)
  Ok 'Initial tier is Silver'                     ($reg.user.tier -eq 'Silver')

  Write-Host ""
  Write-Host "== 5. /api/me echoes the new user (session works) ==" -ForegroundColor Cyan
  $me1 = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $sess
  Ok '/api/me returns the logged-in user' ($me1.user -and $me1.user.email -eq 'sam@example.com')
  Ok '/api/me reports accountType'        ($me1.user.accountType -eq 'supporter')

  Write-Host ""
  Write-Host "== 6. Logout clears the session ==" -ForegroundColor Cyan
  $null = Invoke-RestMethod -Uri ($Base + '/api/logout') -Method Post -WebSession $sess
  $me2 = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $sess
  Ok '/api/me.user is null after logout' ($null -eq $me2.user)

  Write-Host ""
  Write-Host "== 7. Re-login as supporter keeps points + accountType ==" -ForegroundColor Cyan
  $login = Invoke-RestMethod -Uri ($Base + '/api/login') -Method Post -ContentType 'application/json' -WebSession $sess `
    -Body (@{ email='sam@example.com'; password='abcd' } | ConvertTo-Json)
  Ok 'Login returns the user'               ($login.user.email -eq 'sam@example.com')
  Ok 'accountType persisted through login'  ($login.user.accountType -eq 'supporter')

  Write-Host ""
  Write-Host "== 8. Duplicate email is rejected ==" -ForegroundColor Cyan
  $dupCode = 0
  try {
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' `
      -Body (@{ name='Sam 2'; email='sam@example.com'; password='abcd' } | ConvertTo-Json)
  } catch { $dupCode = Code $_ }
  Ok 'Duplicate email returns 409' ($dupCode -eq 409) ('got ' + $dupCode)

  Write-Host ""
  Write-Host "== 9. Weak password is rejected ==" -ForegroundColor Cyan
  $weakCode = 0
  try {
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' `
      -Body (@{ name='Weak'; email='weak@example.com'; password='x' } | ConvertTo-Json)
  } catch { $weakCode = Code $_ }
  Ok 'Weak password returns 400' ($weakCode -eq 400) ('got ' + $weakCode)

  Write-Host ""
  Write-Host "== 10. Public model gallery + email verification ==" -ForegroundColor Cyan
  Ok 'GET / contains #modelsGrid placeholder'   ($html.Content -match 'id="modelsGrid"')
  $playersHtml = Invoke-WebRequest -Uri ($Base + '/players.html') -UseBasicParsing
  Ok 'GET /players.html contains #modelsGrid'   ($playersHtml.Content -match 'id="modelsGrid"')

  $mHtml = Invoke-WebRequest -Uri ($Base + '/m.html') -UseBasicParsing
  Ok 'GET /m.html returns 200'                  ($mHtml.StatusCode -eq 200)
  Ok 'm.html has #mProfile placeholder'         ($mHtml.Content -match 'id="mProfile"')

  $publicModels = Invoke-RestMethod -Uri ($Base + '/api/models')
  Ok '/api/models returns models array (anon)'  ($null -ne $publicModels.models)

  $anonProfCode = 0
  try { $null = Invoke-RestMethod -Uri ($Base + '/api/models/anything') } catch { $anonProfCode = Code $_ }
  Ok 'Anonymous /api/models/{slug} returns 401 or 404' ($anonProfCode -in @(401,404)) ('got ' + $anonProfCode)

  $samMe = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $sess
  Ok 'New supporter is unverified by default'   ($samMe.user.emailVerified -eq $false)
  Ok 'Public-User exposes slug field'           ($null -ne $samMe.user.slug)

  Write-Host ""
  Write-Host "== 11. Feedback widget always-on ==" -ForegroundColor Cyan
  $feedbackJs = Invoke-WebRequest -Uri ($Base + '/js/feedback.js') -UseBasicParsing
  Ok 'GET /js/feedback.js returns 200'           ($feedbackJs.StatusCode -eq 200)
  Ok 'feedback.js exports initFeedback'          ($feedbackJs.Content -match 'export function initFeedback')

  $layoutJs = Invoke-WebRequest -Uri ($Base + '/js/layout.js') -UseBasicParsing
  Ok 'layout.js wires initFeedback()'            ($layoutJs.Content -match 'initFeedback\(\)')

  $fbBody = @{ type='idea'; message='manual-verify ping'; page='/' } | ConvertTo-Json
  $fbAnon = Invoke-RestMethod -Uri ($Base + '/api/feedback') -Method Post -ContentType 'application/json' -Body $fbBody
  Ok 'Anonymous feedback POST returns ok'        ($fbAnon.ok -eq $true)

  $fbAdmin403 = 0
  try { $null = Invoke-RestMethod -Uri ($Base + '/api/admin/feedback') } catch { $fbAdmin403 = Code $_ }
  Ok 'Anonymous /api/admin/feedback -> 403'      ($fbAdmin403 -eq 403) ('got ' + $fbAdmin403)

  Write-Host ""
  Write-Host ("== Manual verify summary: " + $pass + ' passed, ' + $fail + ' failed ==') -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
}
finally {
  try { Stop-Process -Id $sp.Id -Force -ErrorAction SilentlyContinue } catch {}
  Start-Sleep -Milliseconds 500
  if ($fail -eq 0) { Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue }
  else { Write-Host ("Temp dir kept: " + $TestDir) }
}
if ($fail -ne 0) { exit 1 }
