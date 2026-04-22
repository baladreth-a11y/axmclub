# AurumClub end-to-end test (PowerShell 5.1 compatible).
# Spawns an isolated server on port 5175 with its own data folder,
# runs the full user flow, writes e2e-results.log, then cleans up.

$ErrorActionPreference = 'Stop'

$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestDir = Join-Path $env:TEMP ('aurum-e2e-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$LogPath = Join-Path $Root 'e2e-results.log'
$Port    = 5175
$Base    = 'http://localhost:' + $Port

$script:pass  = 0
$script:fail  = 0
$script:lines = @()

function Log {
    param([string]$msg, [string]$color = 'White')
    $script:lines += $msg
    Write-Host $msg -ForegroundColor $color
}

function Check {
    param([string]$name, [bool]$cond, [string]$detail = '')
    if ($cond) {
        $script:pass++
        Log ('  [PASS] ' + $name) 'Green'
    }
    else {
        $script:fail++
        $suffix = ''
        if ($detail) { $suffix = ' :: ' + $detail }
        Log ('  [FAIL] ' + $name + $suffix) 'Red'
    }
}

function Section {
    param([string]$title)
    Log ''
    Log ('== ' + $title) 'Cyan'
}

function JsonBody {
    param([hashtable]$h)
    return ($h | ConvertTo-Json -Compress)
}

function StatusCodeOf {
    param($exception)
    try { return [int]$exception.Exception.Response.StatusCode.Value__ }
    catch { return 0 }
}

Log ('AurumClub E2E — ' + (Get-Date -Format o)) 'Yellow'
Log ('Test dir: ' + $TestDir)

# Copy project into an isolated temp directory so it has a fresh data/ folder.
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
Copy-Item (Join-Path $Root 'server.ps1') (Join-Path $TestDir 'server.ps1')
Copy-Item (Join-Path $Root 'index.html') (Join-Path $TestDir 'index.html') -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root 'styles.css') (Join-Path $TestDir 'styles.css') -ErrorAction SilentlyContinue
Copy-Item -Recurse (Join-Path $Root 'js') (Join-Path $TestDir 'js') -ErrorAction SilentlyContinue

$serverScript = Join-Path $TestDir 'server.ps1'
$outLog       = Join-Path $TestDir 'out.log'
$errLog       = Join-Path $TestDir 'err.log'
$serverArgs   = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$serverScript,'-Port',$Port)

$serverProc = Start-Process -FilePath 'powershell' -ArgumentList $serverArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog

Start-Sleep -Seconds 2
Log ('Server PID: ' + $serverProc.Id)

try {
    # Wait for listener
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $null = Invoke-RestMethod -Uri ($Base + '/api/stats') -TimeoutSec 2
            $ready = $true
            break
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $ready) { throw 'Server never became reachable on ' + $Base }

    Section '1. Initial state (no users yet)'
    $stats = Invoke-RestMethod -Uri ($Base + '/api/stats')
    Check 'Initial members == 0' ($stats.members -eq 0) ('got ' + $stats.members)
    Check 'Initial spins == 0'   ($stats.spins   -eq 0) ('got ' + $stats.spins)

    $lb0 = Invoke-RestMethod -Uri ($Base + '/api/leaderboard')
    Check 'Initial leaderboard is empty' (@($lb0.leaderboard).Count -eq 0)

    Section '2. Register Alice'
    $aliceSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $aliceBody = JsonBody @{ name='Alice'; email='alice@example.com'; password='abcd' }
    $reg = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body $aliceBody
    Check 'Alice created with name' ($reg.user.name -eq 'Alice')   ('got ' + $reg.user.name)
    Check 'Alice starts at 0 pts'   ($reg.user.points -eq 0)       ('got ' + $reg.user.points)
    Check 'Alice tier is Silver'    ($reg.user.tier -eq 'Silver')  ('got ' + $reg.user.tier)

    $me = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $aliceSession
    Check '/api/me returns Alice after register' ($me.user -and $me.user.email -eq 'alice@example.com')

    $stats1 = Invoke-RestMethod -Uri ($Base + '/api/stats')
    Check 'Stats.members == 1 after register' ($stats1.members -eq 1) ('got ' + $stats1.members)

    Section '3. Duplicate registration rejected'
    $dupCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -Body $aliceBody
    }
    catch {
        $dupCode = StatusCodeOf $_
    }
    Check 'Duplicate email returns 409' ($dupCode -eq 409) ('got ' + $dupCode)

    Section '4. Alice spins'
    $spin = Invoke-RestMethod -Uri ($Base + '/api/spin') -Method Post -WebSession $aliceSession
    Check 'Spin returned a valid segment index 0..7' ($spin.index -ge 0 -and $spin.index -le 7) ('got ' + $spin.index)
    Check 'Spin points positive' ($spin.points -gt 0) ('got ' + $spin.points)
    Check 'Spin total at least points' ($spin.total -ge $spin.points)
    Check 'user.points updated' ($spin.user.points -eq $spin.total) ('user=' + $spin.user.points + ' total=' + $spin.total)
    Check 'user.lastSpin recorded' ([long]$spin.user.lastSpin -gt 0)

    $stats2 = Invoke-RestMethod -Uri ($Base + '/api/stats')
    Check 'Stats.spins == 1' ($stats2.spins -eq 1) ('got ' + $stats2.spins)

    $me2 = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $aliceSession
    Check '/api/me points match spin result' ($me2.user.points -eq $spin.total)

    Section '5. Cooldown enforced'
    $cdCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/spin') -Method Post -WebSession $aliceSession
    }
    catch {
        $cdCode = StatusCodeOf $_
    }
    Check 'Second spin returns 429' ($cdCode -eq 429) ('got ' + $cdCode)

    Section '6. Anonymous spin rejected'
    $anonCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/spin') -Method Post
    }
    catch {
        $anonCode = StatusCodeOf $_
    }
    Check 'Anonymous spin returns 401' ($anonCode -eq 401) ('got ' + $anonCode)

    Section '7. Register Bob and spin'
    $bobSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $bobBody = JsonBody @{ name='Bob'; email='bob@example.com'; password='zzzz' }
    $bob = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $bobSession -Body $bobBody
    Check 'Bob created' ($bob.user.email -eq 'bob@example.com')

    $bobSpin = Invoke-RestMethod -Uri ($Base + '/api/spin') -Method Post -WebSession $bobSession
    Check 'Bob spin succeeded' ($bobSpin.total -gt 0)

    Section '8. Leaderboard reflects both users, sorted DESC'
    $lb = Invoke-RestMethod -Uri ($Base + '/api/leaderboard')
    $rows = @($lb.leaderboard)
    Check 'Leaderboard has 2 rows' ($rows.Count -eq 2) ('got ' + $rows.Count)
    if ($rows.Count -ge 2) {
        Check 'Sorted by points desc' ($rows[0].points -ge $rows[1].points) (('[' + $rows[0].points + ', ' + $rows[1].points + ']'))
    }
    $names = ''
    foreach ($r in $rows) { $names = $names + ',' + $r.name }
    Check 'Both names present in leaderboard' (($names -match 'Alice') -and ($names -match 'Bob')) ('names=' + $names)

    Section '9. Login / logout round-trip'
    $null = Invoke-RestMethod -Uri ($Base + '/api/logout') -Method Post -WebSession $aliceSession
    $meAfterLogout = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $aliceSession
    Check 'After logout /api/me.user is null' ($null -eq $meAfterLogout.user)

    $bad = 0
    try {
        $badBody = JsonBody @{ email='alice@example.com'; password='wrong' }
        $null = Invoke-RestMethod -Uri ($Base + '/api/login') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body $badBody
    }
    catch {
        $bad = StatusCodeOf $_
    }
    Check 'Wrong password returns 401' ($bad -eq 401) ('got ' + $bad)

    $goodBody = JsonBody @{ email='alice@example.com'; password='abcd' }
    $loginOk = Invoke-RestMethod -Uri ($Base + '/api/login') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body $goodBody
    Check 'Login returns Alice' ($loginOk.user.email -eq 'alice@example.com')
    Check 'Points persisted across logout/login' ($loginOk.user.points -eq $spin.total) ('expected ' + $spin.total + ' got ' + $loginOk.user.points)

    Section '10. Static files are served'
    $html = Invoke-WebRequest -Uri ($Base + '/') -UseBasicParsing
    Check 'GET / returns 200' ($html.StatusCode -eq 200)
    Check 'GET / contains AurumClub brand' ($html.Content -match 'AurumClub|Aurum')
    Check 'GET / contains #leaderboard section' ($html.Content -match 'id="leaderboard"')
    Check 'GET / contains profile modal view' ($html.Content -match 'data-view="profile"')

    $js = Invoke-WebRequest -Uri ($Base + '/js/main.js') -UseBasicParsing
    Check 'GET /js/main.js returns 200 and JS mime' ($js.StatusCode -eq 200 -and $js.Headers['Content-Type'] -match 'javascript')

    $apiJs = Invoke-WebRequest -Uri ($Base + '/js/api.js') -UseBasicParsing
    Check 'GET /js/api.js returns 200 (module importable)' ($apiJs.StatusCode -eq 200)

    $rewardsJs = Invoke-WebRequest -Uri ($Base + '/js/rewards.js') -UseBasicParsing
    Check 'GET /js/rewards.js returns 200' ($rewardsJs.StatusCode -eq 200)

    $css = Invoke-WebRequest -Uri ($Base + '/styles.css') -UseBasicParsing
    Check 'GET /styles.css returns 200 and CSS mime' ($css.StatusCode -eq 200 -and $css.Headers['Content-Type'] -match 'css')

    $forbidden = 0
    try {
        $null = Invoke-WebRequest -Uri ($Base + '/data/db.json') -UseBasicParsing
    }
    catch {
        $forbidden = StatusCodeOf $_
    }
    Check 'DB file not servable (403)' ($forbidden -eq 403) ('got ' + $forbidden)

    Check 'GET / contains #catalog section' ($html.Content -match 'id="catalog"')

    Section '11. Rewards catalog'
    $catAnon = Invoke-RestMethod -Uri ($Base + '/api/rewards')
    Check 'Catalog has 4 rewards' (@($catAnon.rewards).Count -eq 4) ('got ' + @($catAnon.rewards).Count)
    Check 'Anonymous catalog reports signedIn false' ($catAnon.signedIn -eq $false)
    $ids = ''
    foreach ($r in @($catAnon.rewards)) { $ids = $ids + ',' + $r.id }
    Check 'Catalog contains extra-spin'  ($ids -match 'extra-spin')
    Check 'Catalog contains mystery-bonus' ($ids -match 'mystery-bonus')
    Check 'Catalog contains monthly-box' ($ids -match 'monthly-box')
    Check 'Catalog contains concierge'   ($ids -match 'concierge')

    $aliceCat = Invoke-RestMethod -Uri ($Base + '/api/rewards') -WebSession $aliceSession
    Check 'Logged-in catalog reports signedIn true' ($aliceCat.signedIn -eq $true)

    Section '12. Redeem: auth + validation'
    $anonRedeem = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/redeem') -Method Post -ContentType 'application/json' -Body (JsonBody @{ rewardId='extra-spin' })
    }
    catch { $anonRedeem = StatusCodeOf $_ }
    Check 'Anonymous redeem returns 401' ($anonRedeem -eq 401) ('got ' + $anonRedeem)

    # Fresh user Carol (Silver, 0 pts) for tier/points failure cases.
    $carolSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $carolBody = JsonBody @{ name='Carol'; email='carol@example.com'; password='abcd' }
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $carolSession -Body $carolBody

    $unknownCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/redeem') -Method Post -ContentType 'application/json' -WebSession $carolSession -Body (JsonBody @{ rewardId='does-not-exist' })
    }
    catch { $unknownCode = StatusCodeOf $_ }
    Check 'Unknown rewardId returns 404' ($unknownCode -eq 404) ('got ' + $unknownCode)

    $tierCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/redeem') -Method Post -ContentType 'application/json' -WebSession $carolSession -Body (JsonBody @{ rewardId='concierge' })
    }
    catch { $tierCode = StatusCodeOf $_ }
    Check 'Silver redeeming Platinum-only returns 403' ($tierCode -eq 403) ('got ' + $tierCode)

    $ptsCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/redeem') -Method Post -ContentType 'application/json' -WebSession $carolSession -Body (JsonBody @{ rewardId='extra-spin' })
    }
    catch { $ptsCode = StatusCodeOf $_ }
    Check '0-pt user redeeming 250-pt reward returns 402' ($ptsCode -eq 402) ('got ' + $ptsCode)

    Section '13. Streak + spin history'
    $aliceMe = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $aliceSession
    Check 'Alice streak equals 1 after 1 spin' ($aliceMe.user.streak -eq 1) ('got ' + $aliceMe.user.streak)

    $aliceHist = Invoke-RestMethod -Uri ($Base + '/api/history') -WebSession $aliceSession
    Check 'Alice history has 1 entry' (@($aliceHist.history).Count -eq 1) ('got ' + @($aliceHist.history).Count)

    $aliceRed = Invoke-RestMethod -Uri ($Base + '/api/redemptions') -WebSession $aliceSession
    Check 'Alice has no redemptions yet' (@($aliceRed.redemptions).Count -eq 0) ('got ' + @($aliceRed.redemptions).Count)

    $spinResp = $spin
    Check 'Spin response includes streak field' ($null -ne $spinResp.streak -and $spinResp.streak -ge 1) ('got ' + $spinResp.streak)
    Check 'Spin response includes streakBonus field' ($null -ne $spinResp.streakBonus) ('got ' + $spinResp.streakBonus)

    Section 'Summary'
    Log ('  Passed: ' + $script:pass) 'Green'
    $failColor = 'Green'
    if ($script:fail -ne 0) { $failColor = 'Red' }
    Log ('  Failed: ' + $script:fail) $failColor
}
finally {
    try { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Milliseconds 500
    ($script:lines -join "`r`n") | Out-File -FilePath $LogPath -Encoding UTF8
    Log ('Log written to: ' + $LogPath) 'DarkGray'
    if ($script:fail -eq 0) {
        Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
    }
    else {
        Log ('Temp dir kept for debugging: ' + $TestDir) 'Yellow'
    }
}

if ($script:fail -ne 0) { exit 1 }
