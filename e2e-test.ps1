# AxMclub.com end-to-end test (PowerShell 5.1 compatible).
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

function Invoke-MultipartUpload {
    param(
        [string]$Uri,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [byte[]]$FileBytes,
        [string]$FileName,
        [string]$ContentType
    )

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $sidCookie = $Session.Cookies.GetCookies($Uri) | Where-Object { $_.Name -eq 'sid' } | Select-Object -First 1
    if (-not $sidCookie) { throw 'Session cookie sid is missing.' }

    $handler = $null
    $client = $null
    $multipart = $null
    $fileContent = $null
    try {
        $uriObj = [Uri]$Uri
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.UseCookies = $true
        $handler.CookieContainer = [System.Net.CookieContainer]::new()
        $handler.CookieContainer.Add($uriObj, [System.Net.Cookie]::new('sid', $sidCookie.Value, '/'))
        $client = [System.Net.Http.HttpClient]::new($handler)
        $multipart = [System.Net.Http.MultipartFormDataContent]::new()
        $fileContent = [System.Net.Http.ByteArrayContent]::new($FileBytes)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($ContentType)
        $multipart.Add($fileContent, 'photo', $FileName)

        $resp = $client.PostAsync($Uri, $multipart).GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $json = $null
        if ($text) {
            try { $json = $text | ConvertFrom-Json } catch {}
        }

        return @{
            statusCode = [int]$resp.StatusCode
            body       = $text
            json       = $json
        }
    }
    finally {
        if ($fileContent) { $fileContent.Dispose() }
        if ($multipart)   { $multipart.Dispose() }
        if ($client)      { $client.Dispose() }
        if ($handler)     { $handler.Dispose() }
    }
}

Log ('AxMclub.com E2E — ' + (Get-Date -Format o)) 'Yellow'
Log ('Test dir: ' + $TestDir)

# Copy project into an isolated temp directory so it has a fresh data/ folder.
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
Copy-Item (Join-Path $Root 'server.ps1') (Join-Path $TestDir 'server.ps1')
Copy-Item (Join-Path $Root 'db-sqlite.ps1') (Join-Path $TestDir 'db-sqlite.ps1')
Copy-Item -Recurse (Join-Path $Root 'bin') (Join-Path $TestDir 'bin') -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root 'styles.css') (Join-Path $TestDir 'styles.css') -ErrorAction SilentlyContinue
Copy-Item -Recurse (Join-Path $Root 'js') (Join-Path $TestDir 'js') -ErrorAction SilentlyContinue
# Copy every top-level *.html file so the new dedicated pages
# (model.html, play.html, cam.html, marketplace.html, supporters.html,
# players.html, admin.html plus index.html) are all present.
Get-ChildItem -Path $Root -Filter '*.html' -File |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $TestDir $_.Name) -ErrorAction SilentlyContinue }

$serverScript = Join-Path $TestDir 'server.ps1'
$outLog       = Join-Path $TestDir 'out.log'
$errLog       = Join-Path $TestDir 'err.log'
$serverArgs   = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$serverScript,'-Port',$Port)

# Admin panel needs AURUM_ADMIN_KEY set on the child process. Setting it
# here ensures the spawned server inherits it.
$AdminKey = 'e2e-admin-key-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$env:AURUM_ADMIN_KEY = $AdminKey

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

    Section '3a. Account type on register'
    $acct = $reg.user.accountType
    Check 'Registered user accountType is supporter' ($acct -eq 'supporter') ('got ' + $acct)

    $modelCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -Body (JsonBody @{ name='Model Tester'; email='model@example.com'; password='abcd'; accountType='model' })
    }
    catch { $modelCode = StatusCodeOf $_ }
    Check 'Register with accountType=model returns 403' ($modelCode -eq 403) ('got ' + $modelCode)

    $invalidAcct = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -Body (JsonBody @{ name='Bogus'; email='bogus@example.com'; password='abcd'; accountType='admin' })
    }
    catch { $invalidAcct = StatusCodeOf $_ }
    Check 'Register with accountType=admin returns 400' ($invalidAcct -eq 400) ('got ' + $invalidAcct)

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
    Check 'GET / contains AxMclub brand' ($html.Content -match 'AxMclub')
    Check 'GET / drops #supporters section'    (-not ($html.Content -match 'id="supporters"'))

    $layoutJs = Invoke-WebRequest -Uri ($Base + '/js/layout.js') -UseBasicParsing
    Check 'GET /js/layout.js returns 200' ($layoutJs.StatusCode -eq 200)
    Check 'layout.js contains profile modal view' ($layoutJs.Content -match 'data-view="profile"')

    $js = Invoke-WebRequest -Uri ($Base + '/js/main.js') -UseBasicParsing
    Check 'GET /js/main.js returns 200 and JS mime' ($js.StatusCode -eq 200 -and $js.Headers['Content-Type'] -match 'javascript')

    $apiJs = Invoke-WebRequest -Uri ($Base + '/js/api.js') -UseBasicParsing
    Check 'GET /js/api.js returns 200 (module importable)' ($apiJs.StatusCode -eq 200)

    $rewardsJs = Invoke-WebRequest -Uri ($Base + '/js/rewards.js') -UseBasicParsing
    Check 'GET /js/rewards.js returns 200' ($rewardsJs.StatusCode -eq 200)

    $gateJs = Invoke-WebRequest -Uri ($Base + '/js/gate.js') -UseBasicParsing
    Check 'GET /js/gate.js returns 200' ($gateJs.StatusCode -eq 200)

    $camJs = Invoke-WebRequest -Uri ($Base + '/js/camroom.js') -UseBasicParsing
    Check 'GET /js/camroom.js returns 200' ($camJs.StatusCode -eq 200)

    $tasksJs = Invoke-WebRequest -Uri ($Base + '/js/tasks.js') -UseBasicParsing
    Check 'GET /js/tasks.js returns 200' ($tasksJs.StatusCode -eq 200)

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

    # Home page is trimmed to a model-gallery landing. The other sections
    # live on dedicated pages (/play.html, /marketplace.html, /cam.html,
    # /supporters.html). Only #players + the AxMcamPlayers banner stay
    # on /; the rest is reachable via the navbar.
    Check 'GET / contains #players section'       ($html.Content -match 'id="players"')
    Check 'GET / contains AxMcamPlayers banner'   ($html.Content -match 'AxM.*cam.*Players')
    Check 'GET / drops #marketplace section'      (-not ($html.Content -match 'id="marketplace"'))
    Check 'GET / drops #camroom section'          (-not ($html.Content -match 'id="camroom"'))
    Check 'GET / drops #tasks section'            (-not ($html.Content -match 'id="tasks"'))
    Check 'GET / drops #party-roster section'     (-not ($html.Content -match 'id="party-roster"'))
    Check 'layout.js has dynamic nav players link' ($layoutJs.Content -match 'id="navPlayers"')
    Check 'layout.js has gate overlay markup'      ($layoutJs.Content -match 'id="gate"')
    Check 'layout.js has account-type segment'     ($layoutJs.Content -match 'class="acct-segment"')
    # Static cards have been replaced by the dynamic #modelsGrid; the
    # gallery is populated client-side from GET /api/models. Regression
    # guards: the placeholder is present and the legacy hard-coded
    # `player-photo-N` classes are gone.
    Check 'GET / has #modelsGrid placeholder'      ($html.Content -match 'id="modelsGrid"')
    Check 'GET / no static player-photo-1 markup'  (-not ($html.Content -match 'player-photo-1'))
    Check 'GET / no static player-card markup'     (-not ($html.Content -match 'class="player-card"'))
    Check 'GET / no static affiliate links'        (-not ($html.Content -match 'data-affiliate="crakrevenue"'))
    Check 'GET / has #top-strip section'          ($html.Content -match 'id="top-strip"')
    Check 'GET / has stats widget'                ($html.Content -match 'class="stats-widget"')
    Check 'GET / has Rank stat'                   ($html.Content -match 'id="widgetRank"')
    Check 'GET / has Level stat'                  ($html.Content -match 'id="widgetLevel"')
    Check 'GET / has Tokens stat'                 ($html.Content -match 'id="widgetTokens"')
    Check 'GET / has Get Tokens button'           ($html.Content -match 'id="widgetGetTokens"')
    Check 'GET / has Make Offer button'           ($html.Content -match 'id="widgetMakeOffer"')
    Check 'GET / has event panel'                 ($html.Content -match 'class="event-panel"')

    Section '11. Rewards catalog'
    $catAnon = Invoke-RestMethod -Uri ($Base + '/api/rewards')
    Check 'Catalog has 6 rewards' (@($catAnon.rewards).Count -eq 6) ('got ' + @($catAnon.rewards).Count)
    $catIds = ''
    foreach ($r in @($catAnon.rewards)) { $catIds = $catIds + ',' + $r.id }
    Check 'Catalog contains cam-pass' ($catIds -match 'cam-pass')
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

    Section '14. Cam room pass'
    $camAnonCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/status')
    }
    catch { $camAnonCode = StatusCodeOf $_ }
    Check 'Anonymous /api/cam/status returns 401' ($camAnonCode -eq 401) ('got ' + $camAnonCode)

    # Register a dedicated cam-test user
    $camSess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $camBody = JsonBody @{ name='Dana'; email='dana@example.com'; password='abcd' }
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $camSess -Body $camBody

    $camStatus0 = Invoke-RestMethod -Uri ($Base + '/api/cam/status') -WebSession $camSess
    Check 'Fresh user has no active pass' ($camStatus0.active -eq $false)

    $invalidCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/redeem-password') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ password='NOPE' })
    }
    catch { $invalidCode = StatusCodeOf $_ }
    Check 'Invalid password returns 404' ($invalidCode -eq 404) ('got ' + $invalidCode)

    $camOk = Invoke-RestMethod -Uri ($Base + '/api/cam/redeem-password') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ password='MODEL10' })
    Check 'MODEL10 grants a pass' ($camOk.ok -eq $true)
    Check 'Remaining close to 10 minutes' ($camOk.remainingMs -ge 599000 -and $camOk.remainingMs -le 600000) ('got ' + $camOk.remainingMs)

    $camStatus1 = Invoke-RestMethod -Uri ($Base + '/api/cam/status') -WebSession $camSess
    Check 'Status now reports active pass' ($camStatus1.active -eq $true)

    $dupCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/redeem-password') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ password='MODEL10' })
    }
    catch { $dupCode = StatusCodeOf $_ }
    Check 'Same user redeeming MODEL10 twice returns 409' ($dupCode -eq 409) ('got ' + $dupCode)

    $adminCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/create-password') -Method Post -ContentType 'application/json' -Body (JsonBody @{ password='HACK'; uses=99 })
    }
    catch { $adminCode = StatusCodeOf $_ }
    Check 'create-password without admin key returns 403' ($adminCode -eq 403) ('got ' + $adminCode)

    Section '15. Daily tasks'
    $taskAnon = Invoke-RestMethod -Uri ($Base + '/api/tasks')
    Check 'Anonymous tasks returns 5 items' (@($taskAnon.tasks).Count -eq 5) ('got ' + @($taskAnon.tasks).Count)
    Check 'Anonymous tasks signedIn false' ($taskAnon.signedIn -eq $false)

    $taskList = Invoke-RestMethod -Uri ($Base + '/api/tasks') -WebSession $camSess
    Check 'Signed-in tasks signedIn true' ($taskList.signedIn -eq $true)
    $firstAvail = @($taskList.tasks | Where-Object { $_.available })
    Check 'At least one task available' ($firstAvail.Count -ge 1)

    $anonClaim = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/tasks/claim') -Method Post -ContentType 'application/json' -Body (JsonBody @{ taskId='daily-login' })
    }
    catch { $anonClaim = StatusCodeOf $_ }
    Check 'Anonymous claim returns 401' ($anonClaim -eq 401) ('got ' + $anonClaim)

    $unknownTask = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/tasks/claim') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ taskId='does-not-exist' })
    }
    catch { $unknownTask = StatusCodeOf $_ }
    Check 'Unknown taskId returns 404' ($unknownTask -eq 404) ('got ' + $unknownTask)

    $before = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $camSess
    $claim1 = Invoke-RestMethod -Uri ($Base + '/api/tasks/claim') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ taskId='daily-login' })
    Check 'Claiming daily-login succeeds' ($claim1.ok -eq $true)
    Check 'Claim awards 15 pts' ($claim1.user.points -eq ([int]$before.user.points + 15)) ('delta=' + ($claim1.user.points - [int]$before.user.points))

    $cooldownCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/tasks/claim') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ taskId='daily-login' })
    }
    catch { $cooldownCode = StatusCodeOf $_ }
    Check 'Immediate re-claim returns 429' ($cooldownCode -eq 429) ('got ' + $cooldownCode)

    $profileClaim = Invoke-RestMethod -Uri ($Base + '/api/tasks/claim') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ taskId='complete-profile' })
    Check 'One-time task awards 50 pts' ($profileClaim.reward -eq 50) ('got ' + $profileClaim.reward)
    $onceCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/tasks/claim') -Method Post -ContentType 'application/json' -WebSession $camSess -Body (JsonBody @{ taskId='complete-profile' })
    }
    catch { $onceCode = StatusCodeOf $_ }
    Check 'One-time task claimed twice returns 409' ($onceCode -eq 409) ('got ' + $onceCode)

    Section '17. Admin panel'
    # Anonymous (no x-admin-key) must be blocked on every admin endpoint.
    $adminAnon = 0
    try { $null = Invoke-RestMethod -Uri ($Base + '/api/admin/passwords') } catch { $adminAnon = StatusCodeOf $_ }
    Check 'Anonymous GET /api/admin/passwords returns 403' ($adminAnon -eq 403) ('got ' + $adminAnon)

    $adminHead = @{ 'x-admin-key' = $AdminKey }

    # Passwords list: includes the three seeded codes.
    $pwList = Invoke-RestMethod -Uri ($Base + '/api/admin/passwords') -Headers $adminHead
    $codes  = ''
    foreach ($p in @($pwList.passwords)) { $codes = $codes + ',' + $p.code }
    Check 'Admin password list is non-empty' (@($pwList.passwords).Count -gt 0) ('count=' + @($pwList.passwords).Count)
    Check 'List contains MODEL10'           ($codes -match 'MODEL10')
    Check 'List contains OPEN-HOUSE'        ($codes -match 'OPEN-HOUSE')

    # Create a new password via the (now admin-guarded) create-password endpoint.
    $newPw = Invoke-RestMethod -Uri ($Base + '/api/cam/create-password') -Method Post -ContentType 'application/json' -Headers $adminHead -Body (JsonBody @{ password='E2E-PASS'; uses=2; note='from e2e' })
    Check 'Admin can create a new password'  ($newPw.ok -eq $true)
    Check 'Created password is uppercase'    ($newPw.password -eq 'E2E-PASS')
    Check 'Created password has custom note' ($newPw.note -eq 'from e2e')

    # Revoke that password.
    $revoked = Invoke-RestMethod -Uri ($Base + '/api/admin/passwords/revoke') -Method Post -ContentType 'application/json' -Headers $adminHead -Body (JsonBody @{ code='E2E-PASS' })
    Check 'Admin can revoke a password' ($revoked.ok -eq $true)

    # After revoke, redeeming it returns 410 (used up).
    $gone = 0
    $tmpSess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $tmpSess -Body (JsonBody @{ name='Eve'; email='eve@example.com'; password='abcd' })
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/redeem-password') -Method Post -ContentType 'application/json' -WebSession $tmpSess -Body (JsonBody @{ password='E2E-PASS' })
    } catch { $gone = StatusCodeOf $_ }
    Check 'Revoked password returns 410' ($gone -eq 410) ('got ' + $gone)

    # Revoke of unknown code returns 404.
    $revokeMissing = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/admin/passwords/revoke') -Method Post -ContentType 'application/json' -Headers $adminHead -Body (JsonBody @{ code='DOES-NOT-EXIST' })
    } catch { $revokeMissing = StatusCodeOf $_ }
    Check 'Revoking unknown code returns 404' ($revokeMissing -eq 404) ('got ' + $revokeMissing)

    # Offers list (Alice already submitted one earlier in Section 16).
    # But Section 16 is defined AFTER this one in file order; we run it before,
    # so for now at least Alice has no offers -- but future code may add some.
    $offersResp = Invoke-RestMethod -Uri ($Base + '/api/admin/offers') -Headers $adminHead
    Check 'Admin /api/admin/offers returns an array' ($null -ne $offersResp.offers)

    Section '16. Tokens + offers + economy fields'
    $meEcon = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $aliceSession
    Check 'user.tokens defaults to 0'  ($meEcon.user.tokens -eq 0)
    Check 'user.rank defaults to empty' ([string]::IsNullOrEmpty($meEcon.user.rank))
    Check 'user.level equals points'   ($meEcon.user.level -eq [int]$meEcon.user.points)

    $anonBuy = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/tokens/buy') -Method Post -ContentType 'application/json' -Body (JsonBody @{ amount=100 })
    }
    catch { $anonBuy = StatusCodeOf $_ }
    Check 'Anonymous tokens/buy returns 401' ($anonBuy -eq 401) ('got ' + $anonBuy)

    $badAmt = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/tokens/buy') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body (JsonBody @{ amount=37 })
    }
    catch { $badAmt = StatusCodeOf $_ }
    Check 'Invalid pack size returns 400' ($badAmt -eq 400) ('got ' + $badAmt)

    $buy = Invoke-RestMethod -Uri ($Base + '/api/tokens/buy') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body (JsonBody @{ amount=500 })
    Check 'Buying 500 tokens succeeds'           ($buy.ok -eq $true)
    Check 'Tokens balance bumps to 500'           ($buy.user.tokens -eq 500)
    Check 'Level equals points + tokens'          ($buy.user.level -eq ([int]$buy.user.points + 500))

    $anonOffer = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/offer') -Method Post -ContentType 'application/json' -Body (JsonBody @{ message='too short' })
    }
    catch { $anonOffer = StatusCodeOf $_ }
    Check 'Anonymous offer returns 401' ($anonOffer -eq 401) ('got ' + $anonOffer)

    $shortOffer = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/offer') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body (JsonBody @{ message='hi' })
    }
    catch { $shortOffer = StatusCodeOf $_ }
    Check 'Short offer returns 400' ($shortOffer -eq 400) ('got ' + $shortOffer)

    $offerOk = Invoke-RestMethod -Uri ($Base + '/api/offer') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body (JsonBody @{ target='Nova'; message='Looking for a custom 10-minute set.' })
    Check 'Valid offer is accepted'            ($offerOk.ok -eq $true)
    Check 'Offer has a generated id'           ($offerOk.offer.id -and $offerOk.offer.id.Length -gt 0)
    Check 'Offer status starts as pending'     ($offerOk.offer.status -eq 'pending')

    Section '18. Admin offer status updates'
    $adminHead2 = @{ 'x-admin-key' = $AdminKey }
    $adminOffers = Invoke-RestMethod -Uri ($Base + '/api/admin/offers') -Headers $adminHead2
    Check 'Admin now sees at least one offer' (@($adminOffers.offers).Count -ge 1) ('got ' + @($adminOffers.offers).Count)

    $firstOffer = @($adminOffers.offers)[0]
    $badStatus = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/admin/offers/status') -Method Post -ContentType 'application/json' -Headers $adminHead2 -Body (JsonBody @{ userEmail=$firstOffer.from; offerId=$firstOffer.id; status='nope' })
    } catch { $badStatus = StatusCodeOf $_ }
    Check 'Invalid offer status returns 400' ($badStatus -eq 400) ('got ' + $badStatus)

    $accepted = Invoke-RestMethod -Uri ($Base + '/api/admin/offers/status') -Method Post -ContentType 'application/json' -Headers $adminHead2 -Body (JsonBody @{ userEmail=$firstOffer.from; offerId=$firstOffer.id; status='accepted' })
    Check 'Offer accepted via admin' ($accepted.status -eq 'accepted')

    $reread = Invoke-RestMethod -Uri ($Base + '/api/admin/offers') -Headers $adminHead2
    $refreshed = @($reread.offers) | Where-Object { $_.id -eq $firstOffer.id } | Select-Object -First 1
    Check 'Offer status persists as accepted' ($refreshed.status -eq 'accepted')

    Section '19. Multi-page static files'
    foreach ($page in @('model.html','play.html','cam.html','marketplace.html','supporters.html','players.html')) {
        $resp = Invoke-WebRequest -Uri ($Base + '/' + $page) -UseBasicParsing
        Check ("GET /$page returns 200") ($resp.StatusCode -eq 200)
        # Headers['Content-Type'] can be a string or string[] depending on the
        # PowerShell host; normalize with @() + -join '' before regex matching.
        $ct = ((@($resp.Headers['Content-Type'])) -join '')
        Check ("GET /$page is HTML")     ([bool]($ct -match 'text/html'))
    }
    $modelHtml = (Invoke-WebRequest -Uri ($Base + '/model.html') -UseBasicParsing).Content
    Check 'model.html has profile form'           ($modelHtml -match 'id="profileForm"')
    Check 'model.html has password manager form'  ($modelHtml -match 'id="newPasswordForm"')
    Check 'model.html has offers body'            ($modelHtml -match 'id="offersBody"')
    Check 'model.html has stats hooks'            ($modelHtml -match 'id="statPwIssued"')
    $camHtml = (Invoke-WebRequest -Uri ($Base + '/cam.html') -UseBasicParsing).Content
    Check 'cam.html has #camroom section'         ($camHtml -match 'id="camroom"')
    Check 'cam.html has navHost placeholder'      ($camHtml -match 'id="navHost"')
    $playHtml = (Invoke-WebRequest -Uri ($Base + '/play.html') -UseBasicParsing).Content
    Check 'play.html has #tasks section'          ($playHtml -match 'id="tasks"')
    Check 'play.html has #roulette section'       ($playHtml -match 'id="roulette"')
    Check 'GET /js/layout.js returns 200'         ((Invoke-WebRequest -Uri ($Base + '/js/layout.js') -UseBasicParsing).StatusCode -eq 200)
    Check 'GET /js/model-dashboard.js returns 200' ((Invoke-WebRequest -Uri ($Base + '/js/model-dashboard.js') -UseBasicParsing).StatusCode -eq 200)

    Check 'layout.js has Model dashboard nav link' ($layoutJs.Content -match 'id="navModelLink"')

    Section '20. Model dashboard API'
    # Anonymous (no session) is 401 on every model endpoint.
    foreach ($call in @(
        @{ method='GET';  url='/api/model/profile' },
        @{ method='GET';  url='/api/model/passwords' },
        @{ method='GET';  url='/api/model/offers' },
        @{ method='GET';  url='/api/model/stats' }
    )) {
        $code = 0
        try {
            $null = Invoke-RestMethod -Uri ($Base + $call.url) -Method $call.method
        } catch { $code = StatusCodeOf $_ }
        Check ('Anonymous ' + $call.method + ' ' + $call.url + ' returns 401') ($code -eq 401) ('got ' + $code)
    }

    # A signed-in supporter is 403 on every model endpoint.
    $supSess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $supSess `
        -Body (JsonBody @{ name='Sara'; email='sara@example.com'; password='abcd' })
    $supCode = 0
    try { $null = Invoke-RestMethod -Uri ($Base + '/api/model/profile') -WebSession $supSess } catch { $supCode = StatusCodeOf $_ }
    Check 'Supporter GET /api/model/profile returns 403' ($supCode -eq 403) ('got ' + $supCode)

    # Promote a user to model via the admin endpoint.
    $modelSess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $modelSess `
        -Body (JsonBody @{ name='Nova'; email='nova@example.com'; password='abcd' })
    $promoted = Invoke-RestMethod -Uri ($Base + '/api/admin/users/adjust') -Method Post -ContentType 'application/json' -Headers $adminHead -Body (JsonBody @{ email='nova@example.com'; accountType='model' })
    Check 'Promotion to model succeeds' ($promoted.user.accountType -eq 'model') ('got ' + $promoted.user.accountType)

    # The model session needs to refresh /api/me after the admin promoted them.
    $modelMe = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $modelSess
    Check 'Promoted user reads as model on /api/me' ($modelMe.user.accountType -eq 'model') ('got ' + $modelMe.user.accountType)

    # Profile read.
    $prof = Invoke-RestMethod -Uri ($Base + '/api/model/profile') -WebSession $modelSess
    Check 'Model can read own profile'        ($prof.user.email -eq 'nova@example.com')
    Check 'Profile defaults bio to empty'     ($prof.user.bio -eq '' -or $null -eq $prof.user.bio)

    # Profile update.
    $upd = Invoke-RestMethod -Uri ($Base + '/api/model/profile') -Method Post -ContentType 'application/json' -WebSession $modelSess `
        -Body (JsonBody @{ bio='Friday nights, jazz + synth.'; brandColor='#ff66aa'; socials=@{ telegram='https://t.me/nova_demo' } })
    Check 'Profile update returns ok'           ($upd.ok -eq $true)
    Check 'Bio persists in user payload'        ($upd.user.bio -eq 'Friday nights, jazz + synth.')
    Check 'Brand color persists'                ($upd.user.brandColor -eq '#ff66aa')
    Check 'Telegram social persists'            ($upd.user.socials.telegram -eq 'https://t.me/nova_demo')

    # Bad brand color is rejected.
    $badProf = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/model/profile') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ brandColor='not-a-color' })
    } catch { $badProf = StatusCodeOf $_ }
    Check 'Empty profile body returns 400 (bad color rejected)' ($badProf -eq 400) ('got ' + $badProf)

    # Create a model-owned password.
    $createdPw = Invoke-RestMethod -Uri ($Base + '/api/model/passwords') -Method Post -ContentType 'application/json' -WebSession $modelSess `
        -Body (JsonBody @{ password='nova-vip'; uses=3; note='VIPs only' })
    Check 'Model can create a password'         ($createdPw.ok -eq $true)
    Check 'Created password is uppercase'        ($createdPw.password -eq 'NOVA-VIP')
    Check 'createdBy stamped with model email'   ($createdPw.createdBy -eq 'nova@example.com')

    # Listing model passwords excludes system + admin codes.
    $myPw = Invoke-RestMethod -Uri ($Base + '/api/model/passwords') -WebSession $modelSess
    $myCodes = ''
    foreach ($p in @($myPw.passwords)) { $myCodes = $myCodes + ',' + $p.code }
    Check 'Model password list contains NOVA-VIP'   ($myCodes -match 'NOVA-VIP')
    Check 'Model password list excludes MODEL10'    ($myCodes -notmatch 'MODEL10')
    Check 'Model password list excludes OPEN-HOUSE' ($myCodes -notmatch 'OPEN-HOUSE')

    # Duplicate code rejected.
    $dupModel = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/model/passwords') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ password='nova-vip'; uses=1 })
    } catch { $dupModel = StatusCodeOf $_ }
    Check 'Duplicate password code returns 409' ($dupModel -eq 409) ('got ' + $dupModel)

    # Revoke someone else's password (system-seeded MODEL10) -> 403.
    $stealCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/model/passwords/revoke') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ code='MODEL10' })
    } catch { $stealCode = StatusCodeOf $_ }
    Check 'Model revoking someone else password returns 403' ($stealCode -eq 403) ('got ' + $stealCode)

    # Revoke own password.
    $revOwn = Invoke-RestMethod -Uri ($Base + '/api/model/passwords/revoke') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ code='NOVA-VIP' })
    Check 'Model can revoke own password' ($revOwn.ok -eq $true)

    # Offers: ensure the offer Alice sent earlier in section 16 (target='Nova')
    # appears in the model's targeted-offers feed.
    $myOffers = Invoke-RestMethod -Uri ($Base + '/api/model/offers') -WebSession $modelSess
    Check 'Model sees at least one targeted offer' (@($myOffers.offers).Count -ge 1) ('got ' + @($myOffers.offers).Count)
    $myOffer = @($myOffers.offers)[0]
    Check 'Offer is addressed to Nova' ($myOffer.target -eq 'Nova') ('got ' + $myOffer.target)

    # Bad status rejected.
    $badResp = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/model/offers/respond') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ userEmail=$myOffer.from; offerId=$myOffer.id; status='nope' })
    } catch { $badResp = StatusCodeOf $_ }
    Check 'Invalid model offer status returns 400' ($badResp -eq 400) ('got ' + $badResp)

    # Decline own targeted offer.
    $declined = Invoke-RestMethod -Uri ($Base + '/api/model/offers/respond') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ userEmail=$myOffer.from; offerId=$myOffer.id; status='declined' })
    Check 'Model can decline targeted offer' ($declined.status -eq 'declined')

    # Stats reflect issued + redeemed counts.
    $modelStats = Invoke-RestMethod -Uri ($Base + '/api/model/stats') -WebSession $modelSess
    Check 'Stats: passwordsIssued >= 1'  ($modelStats.passwordsIssued -ge 1) ('got ' + $modelStats.passwordsIssued)
    Check 'Stats: offersTotal >= 1'      ($modelStats.offersTotal     -ge 1) ('got ' + $modelStats.offersTotal)
    Check 'Stats: offersDeclined >= 1'   ($modelStats.offersDeclined  -ge 1) ('got ' + $modelStats.offersDeclined)

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

    Section '21. Models gallery + verification + uploads'

    # GET /api/models is fully public (no auth, no admin key).
    $modelsList = Invoke-RestMethod -Uri ($Base + '/api/models')
    Check '/api/models returns models array' ($null -ne $modelsList.models)
    $novaCard = @($modelsList.models) | Where-Object { $_.slug -eq 'nova' } | Select-Object -First 1
    Check 'Nova appears in /api/models'      ($null -ne $novaCard)
    Check 'Public model card omits email'    ($null -eq $novaCard.email -or $novaCard.email -eq '')
    Check 'Public model card omits points'   ($null -eq $novaCard.points)

    # Profile update with gender + photoUrl (from the model session set up earlier).
    $genUpd = Invoke-RestMethod -Uri ($Base + '/api/model/profile') -Method Post -ContentType 'application/json' -WebSession $modelSess `
        -Body (JsonBody @{ gender='female' })
    Check 'Gender persists on profile' ($genUpd.user.gender -eq 'female')

    $badGender = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/model/profile') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ gender='unicorn' })
    } catch { $badGender = StatusCodeOf $_ }
    Check 'Bad gender returns 400' ($badGender -eq 400) ('got ' + $badGender)

    # Anonymous /api/models/nova returns 401 with reason='sign-in'.
    # PS7's Invoke-RestMethod surfaces the response body on $_.ErrorDetails.Message;
    # PS5.1 falls back to the response stream on $_.Exception.Response.
    function Read-ErrorJson($errRecord) {
        if ($errRecord.ErrorDetails -and $errRecord.ErrorDetails.Message) {
            try { return ($errRecord.ErrorDetails.Message | ConvertFrom-Json) } catch { return $null }
        }
        try {
            $stream = $errRecord.Exception.Response.GetResponseStream()
            if (-not $stream) { return $null }
            $sr = New-Object IO.StreamReader($stream)
            $body = $sr.ReadToEnd(); $sr.Close()
            return ($body | ConvertFrom-Json)
        } catch { return $null }
    }

    $anonProf = 0
    $anonProfReason = ''
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/models/nova')
    } catch {
        $anonProf = StatusCodeOf $_
        $j = Read-ErrorJson $_
        if ($j) { $anonProfReason = [string]$j.reason }
    }
    Check 'Anonymous /api/models/nova -> 401'           ($anonProf -eq 401)        ('got ' + $anonProf)
    Check 'Anonymous /api/models/nova reason sign-in'   ($anonProfReason -eq 'sign-in') ('got ' + $anonProfReason)

    # New unverified supporter -> 403 with reason='verify-email'.
    $unvSess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $unvSess `
        -Body (JsonBody @{ name='Una'; email='una@example.com'; password='abcd' })
    $unvMe = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $unvSess
    Check 'New supporter is unverified by default' ($unvMe.user.emailVerified -eq $false)

    $unvProf = 0; $unvReason = ''
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/models/nova') -WebSession $unvSess
    } catch {
        $unvProf = StatusCodeOf $_
        $j = Read-ErrorJson $_
        if ($j) { $unvReason = [string]$j.reason }
    }
    Check 'Unverified user /api/models/nova -> 403'      ($unvProf -eq 403)            ('got ' + $unvProf)
    Check 'Unverified user reason = verify-email'        ($unvReason -eq 'verify-email') ('got ' + $unvReason)

    # Verification flow. POST /api/verify/start writes a [verify-link]
    # entry to stdout (the harness redirects stdout to $outLog). We tail
    # the file, extract the token, and confirm via GET.
    $startRes = Invoke-RestMethod -Uri ($Base + '/api/verify/start') -Method Post -WebSession $unvSess
    Check '/api/verify/start ok'  ($startRes.ok -eq $true)
    Check '/api/verify/start sent' ($startRes.sent -eq $true)

    Start-Sleep -Milliseconds 250
    $logText = ''
    if (Test-Path $outLog) { $logText = Get-Content $outLog -Raw -ErrorAction SilentlyContinue }
    $matches = [regex]::Matches($logText, '\[verify-link\][^?]*\?token=([A-Za-z0-9%]+)')
    $token = ''
    if ($matches.Count -gt 0) { $token = [uri]::UnescapeDataString($matches[$matches.Count - 1].Groups[1].Value) }
    Check 'Verify link captured from stdout' ($token -and $token.Length -gt 0) ('len=' + $token.Length)

    if ($token) {
        $confirmHtml = Invoke-WebRequest -Uri ($Base + '/api/verify/confirm?token=' + [uri]::EscapeDataString($token)) -UseBasicParsing -WebSession $unvSess
        Check 'Confirm returns 200'           ($confirmHtml.StatusCode -eq 200)
        Check 'Confirm body says Email verified' ($confirmHtml.Content -match 'Email verified')
    }

    $unvAfter = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $unvSess
    Check 'After confirm /api/me.user.emailVerified is true' ($unvAfter.user.emailVerified -eq $true)

    $verifiedProf = Invoke-RestMethod -Uri ($Base + '/api/models/nova') -WebSession $unvSess
    Check 'Verified user can read /api/models/nova'   ($verifiedProf.model.slug -eq 'nova')
    Check 'Per-model detail includes gallery field'   ($null -ne $verifiedProf.model.gallery)


    # 1x1 transparent PNG (67 bytes), base64-encoded.
    $pngB64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII='
    $pngBytes = [Convert]::FromBase64String($pngB64)

    $upUrl = $Base + '/api/model/photo'
    $upResult = Invoke-MultipartUpload -Uri $upUrl -Session $modelSess -FileBytes $pngBytes -FileName 'main.png' -ContentType 'image/png'
    $upJson = $upResult.json
    if ($upResult.statusCode -ne 200) {
        $err = $upResult.body
        if ($upJson -and $upJson.error) { $err = $upJson.error }
        Check 'Main photo upload ok' $false ('http=' + $upResult.statusCode + ' err=' + $err)
    }
    if ($upResult.statusCode -eq 200 -and $upJson) {
        Check 'Main photo upload ok'                 ($upJson.ok -eq $true)
        Check 'Main photo URL under /uploads/'       ($upJson.photoUrl -match '^/uploads/models/nova/main\.png$') ('got ' + $upJson.photoUrl)
        Check 'Public-User photoUrl reflects upload' ($upJson.user.photoUrl -eq $upJson.photoUrl)

        $servePhoto = Invoke-WebRequest -Uri ($Base + $upJson.photoUrl) -UseBasicParsing
        $serveCt = ((@($servePhoto.Headers['Content-Type'])) -join '')
        Check 'Uploaded photo serves with image mime' ($serveCt -match 'image/png') ('got ' + $serveCt)
        Check 'Uploaded photo bytes match upload size' ($servePhoto.RawContentLength -eq $pngBytes.Length) ('got ' + $servePhoto.RawContentLength)
    }

    # Bad mime gets rejected.
    $badResult = Invoke-MultipartUpload -Uri $upUrl -Session $modelSess -FileBytes ([Text.Encoding]::ASCII.GetBytes('hello')) -FileName 'evil.txt' -ContentType 'text/plain'
    Check 'Unsupported upload type returns 415' ($badResult.statusCode -eq 415) ('got ' + $badResult.statusCode)

    # Gallery add then remove.
    $galResult = Invoke-MultipartUpload -Uri ($Base + '/api/model/gallery/add') -Session $modelSess -FileBytes $pngBytes -FileName 'gal.png' -ContentType 'image/png'
    $galJson = $galResult.json
    Check 'Gallery add ok'                ($galResult.statusCode -eq 200 -and $galJson.ok -eq $true) ('got ' + $galResult.statusCode)
    if ($galResult.statusCode -eq 200 -and $galJson) {
        Check 'Gallery has at least one item' (@($galJson.gallery).Count -ge 1)

        $galUrl = (@($galJson.gallery))[-1].url
        $galServe = Invoke-WebRequest -Uri ($Base + $galUrl) -UseBasicParsing
        Check 'Gallery photo serves 200' ($galServe.StatusCode -eq 200)

        $galRm = Invoke-RestMethod -Uri ($Base + '/api/model/gallery/remove') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ url = $galUrl })
        Check 'Gallery remove ok' ($galRm.ok -eq $true)
        $galGone = 0
        try {
            $null = Invoke-WebRequest -Uri ($Base + $galUrl) -UseBasicParsing
        } catch { $galGone = StatusCodeOf $_ }
        Check 'Removed gallery photo returns 404' ($galGone -eq 404) ('got ' + $galGone)
    }

    # Removing someone else's URL is rejected.
    $foreignRm = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/model/gallery/remove') -Method Post -ContentType 'application/json' -WebSession $modelSess -Body (JsonBody @{ url = '/uploads/models/someone/g1.png' })
    } catch { $foreignRm = StatusCodeOf $_ }
    Check 'Removing foreign gallery URL returns 403' ($foreignRm -eq 403) ('got ' + $foreignRm)

    # Admin verify shortcut flips the flag without an email round-trip.
    $adminVerify = Invoke-RestMethod -Uri ($Base + '/api/admin/users/verify') -Method Post -ContentType 'application/json' -Headers $adminHead -Body (JsonBody @{ email = 'alice@example.com' })
    Check 'Admin verify endpoint flips flag' ($adminVerify.user.emailVerified -eq $true)

    # Static page serving for m.html.
    $mHtmlResp = Invoke-WebRequest -Uri ($Base + '/m.html') -UseBasicParsing
    Check 'GET /m.html returns 200'              ($mHtmlResp.StatusCode -eq 200)
    Check 'm.html has #mProfile placeholder'     ($mHtmlResp.Content -match 'id="mProfile"')
    Check 'GET /js/models.js returns 200'        ((Invoke-WebRequest -Uri ($Base + '/js/models.js') -UseBasicParsing).StatusCode -eq 200)
    Check 'GET /js/verify.js returns 200'        ((Invoke-WebRequest -Uri ($Base + '/js/verify.js') -UseBasicParsing).StatusCode -eq 200)
    Check 'GET /js/model-profile.js returns 200' ((Invoke-WebRequest -Uri ($Base + '/js/model-profile.js') -UseBasicParsing).StatusCode -eq 200)

    Section '22. Feedback widget'

    # Anonymous POST works (no auth required).
    $fbAnon = Invoke-RestMethod -Uri ($Base + '/api/feedback') -Method Post -ContentType 'application/json' `
        -Body (JsonBody @{ type='idea'; message='Wheel is gorgeous'; page='/'; contact='' })
    Check 'Anonymous feedback POST returns ok' ($fbAnon.ok -eq $true)
    Check 'Anonymous feedback returns id'      ([bool]$fbAnon.id)

    # Empty message rejected.
    $emptyFb = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/feedback') -Method Post -ContentType 'application/json' -Body (JsonBody @{ type='bug'; message='   ' })
    } catch { $emptyFb = StatusCodeOf $_ }
    Check 'Empty feedback message returns 400' ($emptyFb -eq 400) ('got ' + $emptyFb)

    # Over-long message rejected.
    $bigMsg = ('x' * 2100)
    $bigFb = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/feedback') -Method Post -ContentType 'application/json' -Body (JsonBody @{ type='bug'; message=$bigMsg })
    } catch { $bigFb = StatusCodeOf $_ }
    Check 'Oversized feedback message returns 400' ($bigFb -eq 400) ('got ' + $bigFb)

    # Signed-in submission carries userEmail through.
    $fbSigned = Invoke-RestMethod -Uri ($Base + '/api/feedback') -Method Post -ContentType 'application/json' -WebSession $aliceSession `
        -Body (JsonBody @{ type='bug'; message='Spin button froze on me'; page='/play.html'; contact='alice@example.com' })
    Check 'Signed-in feedback POST returns ok' ($fbSigned.ok -eq $true)

    # Admin GET shows entries.
    $fbAdmin = Invoke-RestMethod -Uri ($Base + '/api/admin/feedback') -Headers $adminHead
    Check 'Admin feedback GET returns array' ($null -ne $fbAdmin.feedback)
    Check 'Admin feedback GET count >= 2'    ($fbAdmin.count -ge 2) ('got ' + $fbAdmin.count)
    $bugEntry = @($fbAdmin.feedback) | Where-Object { $_.type -eq 'bug' -and $_.message -match 'Spin button' } | Select-Object -First 1
    Check 'Bug entry recorded with userEmail'  ($bugEntry -and $bugEntry.userEmail -eq 'alice@example.com')
    Check 'Bug entry default status open'      ($bugEntry -and $bugEntry.status -eq 'open')

    # Admin resolve flips the status.
    $fbResolve = Invoke-RestMethod -Uri ($Base + '/api/admin/feedback/resolve') -Method Post -ContentType 'application/json' -Headers $adminHead `
        -Body (JsonBody @{ id=$bugEntry.id; status='resolved' })
    Check 'Admin resolve returns ok'        ($fbResolve.ok -eq $true)
    Check 'Admin resolve returns status'    ($fbResolve.status -eq 'resolved')
    $fbAdmin2 = Invoke-RestMethod -Uri ($Base + '/api/admin/feedback') -Headers $adminHead
    $resolved = @($fbAdmin2.feedback) | Where-Object { $_.id -eq $bugEntry.id } | Select-Object -First 1
    Check 'Resolved entry persists status'  ($resolved -and $resolved.status -eq 'resolved')

    # Unknown id -> 404.
    $fbBad = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/admin/feedback/resolve') -Method Post -ContentType 'application/json' -Headers $adminHead -Body (JsonBody @{ id='nope-not-real'; status='resolved' })
    } catch { $fbBad = StatusCodeOf $_ }
    Check 'Resolve unknown id returns 404' ($fbBad -eq 404) ('got ' + $fbBad)

    # Admin endpoints require the admin key.
    $fbAuth = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/admin/feedback')
    } catch { $fbAuth = StatusCodeOf $_ }
    Check 'Anonymous /api/admin/feedback returns 403' ($fbAuth -eq 403) ('got ' + $fbAuth)

    # Frontend artifact + page mounts. The FAB is injected at runtime
    # by initFeedback() (called from layout.js), so it isn't in static
    # HTML; verify the module is reachable and that layout.js wires it.
    Check 'GET /js/feedback.js returns 200' ((Invoke-WebRequest -Uri ($Base + '/js/feedback.js') -UseBasicParsing).StatusCode -eq 200)
    $layoutSrc = (Invoke-WebRequest -Uri ($Base + '/js/layout.js') -UseBasicParsing).Content
    Check 'layout.js wires initFeedback()' ($layoutSrc -match 'initFeedback\(\)')
    $cssSrc = (Invoke-WebRequest -Uri ($Base + '/styles.css') -UseBasicParsing).Content
    Check 'styles.css ships .feedback-fab'  ($cssSrc -match '\.feedback-fab')

    Section '23. Communicator: presence + 1:1 chat'

    # Anonymous /api/online -> 401 (auth required).
    $onAnon = 0
    try { $null = Invoke-RestMethod -Uri ($Base + '/api/online') } catch { $onAnon = StatusCodeOf $_ }
    Check 'Anonymous /api/online returns 401' ($onAnon -eq 401) ('got ' + $onAnon)

    # Two fresh sessions: chatA + chatB.
    $chatA = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null  = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $chatA `
        -Body (JsonBody @{ name='ChatA'; email='chat-a@example.com'; password='abcd' })
    $chatB = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null  = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $chatB `
        -Body (JsonBody @{ name='ChatB'; email='chat-b@example.com'; password='abcd' })

    # ChatA pings /api/me to refresh lastSeenMs; both should appear online to each other.
    $null = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $chatA
    $onA  = Invoke-RestMethod -Uri ($Base + '/api/online') -WebSession $chatA
    $emails = ''
    foreach ($u in @($onA.users)) { $emails = $emails + ',' + $u.email }
    Check 'Online list includes peer'             ($emails -match 'chat-b@example.com') ('got ' + $emails)
    Check 'Online list excludes self'             (-not ($emails -match 'chat-a@example.com'))
    Check 'Public-Online has cam2cam field'       ([bool](@($onA.users)[0]).PSObject.Properties['cam2cam'])

    # ChatA sends DM to ChatB.
    $sendOk = Invoke-RestMethod -Uri ($Base + '/api/chat/send') -Method Post -ContentType 'application/json' -WebSession $chatA `
        -Body (JsonBody @{ peer='chat-b@example.com'; text='Hello from A!' })
    Check 'Chat send returns ok'                  ($sendOk.ok -eq $true)
    Check 'Chat send returns thread id'           ([bool]$sendOk.threadId)
    Check 'Chat send returns message with id'     ([bool]$sendOk.message -and [bool]$sendOk.message.id)

    # Empty text -> 400.
    $emptyChat = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/chat/send') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ peer='chat-b@example.com'; text='   ' })
    } catch { $emptyChat = StatusCodeOf $_ }
    Check 'Empty chat text returns 400'           ($emptyChat -eq 400) ('got ' + $emptyChat)

    # Self-DM -> 400.
    $selfChat = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/chat/send') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ peer='chat-a@example.com'; text='hi me' })
    } catch { $selfChat = StatusCodeOf $_ }
    Check 'Chatting yourself returns 400'         ($selfChat -eq 400) ('got ' + $selfChat)

    # Unknown peer -> 404.
    $unkPeer = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/chat/send') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ peer='nobody@example.com'; text='hi' })
    } catch { $unkPeer = StatusCodeOf $_ }
    Check 'Sending to unknown peer returns 404'   ($unkPeer -eq 404) ('got ' + $unkPeer)

    # ChatB threads view shows unread=1 with last message preview.
    $bThreads = Invoke-RestMethod -Uri ($Base + '/api/chat/threads') -WebSession $chatB
    Check 'ChatB has at least one thread'         (@($bThreads.threads).Count -ge 1) ('got ' + @($bThreads.threads).Count)
    $bThread = @($bThreads.threads) | Where-Object { $_.peerEmail -eq 'chat-a@example.com' } | Select-Object -First 1
    Check 'ChatB thread points back at ChatA'     ($null -ne $bThread)
    if ($bThread) {
        Check 'ChatB unread is 1'                   ([int]$bThread.unread -eq 1) ('got ' + $bThread.unread)
        Check 'Last message preview matches'        ($bThread.lastMessage -eq 'Hello from A!')
    }
    Check 'Threads payload exposes total unread'  ([int]$bThreads.unread -ge 1)

    # Fetching messages marks the thread as read.
    $bMsgs = Invoke-RestMethod -Uri ($Base + '/api/chat/messages?peer=chat-a@example.com') -WebSession $chatB
    Check 'Messages endpoint returns array'       ($null -ne $bMsgs.messages -and (@($bMsgs.messages)).Count -ge 1)
    Check 'Messages payload exposes peerName'     ($bMsgs.peerName -eq 'ChatA')
    Check 'Messages exposes peerCam2cam flag'     ([bool]$bMsgs.PSObject.Properties['peerCam2cam'])
    $bThreads2 = Invoke-RestMethod -Uri ($Base + '/api/chat/threads') -WebSession $chatB
    $bThread2 = @($bThreads2.threads) | Where-Object { $_.peerEmail -eq 'chat-a@example.com' } | Select-Object -First 1
    Check 'Reading messages clears unread'        ($bThread2 -and [int]$bThread2.unread -eq 0) ('got ' + ($(if ($bThread2) { $bThread2.unread } else { 'none' })))

    # DM policy: ChatB closes inbox; ChatA send -> 403; ChatA can still send if ChatB had previously DM'd — but our flow has ChatA initiating, so 'closed' blocks regardless.
    $polClose = Invoke-RestMethod -Uri ($Base + '/api/chat/policy') -Method Post -ContentType 'application/json' -WebSession $chatB -Body (JsonBody @{ policy='closed' })
    Check 'Set dmPolicy=closed returns ok'         ($polClose.ok -eq $true -and $polClose.dmPolicy -eq 'closed')
    $closedSend = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/chat/send') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ peer='chat-b@example.com'; text='still there?' })
    } catch { $closedSend = StatusCodeOf $_ }
    Check 'Closed inbox blocks further DMs (403)' ($closedSend -eq 403) ('got ' + $closedSend)

    # Restore policy for the rate-limit test.
    $null = Invoke-RestMethod -Uri ($Base + '/api/chat/policy') -Method Post -ContentType 'application/json' -WebSession $chatB -Body (JsonBody @{ policy='open' })

    # Bad policy value -> 400.
    $badPol = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/chat/policy') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ policy='nope' })
    } catch { $badPol = StatusCodeOf $_ }
    Check 'Invalid dmPolicy returns 400'           ($badPol -eq 400) ('got ' + $badPol)

    # Frontend artifacts.
    Check 'GET /js/communicator.js returns 200' ((Invoke-WebRequest -Uri ($Base + '/js/communicator.js') -UseBasicParsing).StatusCode -eq 200)
    Check 'layout.js wires initCommunicator()' ($layoutSrc -match 'initCommunicator\(\)')
    Check 'styles.css ships .comm-fab'         ($cssSrc -match '\.comm-fab')
    Check 'styles.css ships .online-dot'       ($cssSrc -match '\.online-dot')

    Section '24. Cam2cam: signalling pipes'

    # All endpoints require auth.
    $c2cAnonRequest = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/request') -Method Post -ContentType 'application/json' -Body (JsonBody @{ to='chat-b@example.com' })
    } catch { $c2cAnonRequest = StatusCodeOf $_ }
    Check 'Anonymous /api/cam/request returns 401'    ($c2cAnonRequest -eq 401) ('got ' + $c2cAnonRequest)

    $c2cAnonInbox = 0
    try { $null = Invoke-RestMethod -Uri ($Base + '/api/cam/inbox') } catch { $c2cAnonInbox = StatusCodeOf $_ }
    Check 'Anonymous /api/cam/inbox returns 401'      ($c2cAnonInbox -eq 401) ('got ' + $c2cAnonInbox)

    # Both ChatA and ChatB start with cam2cam off (supporters by default).
    $offTry = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/request') -Method Post -ContentType 'application/json' -WebSession $chatA `
            -Body (JsonBody @{ to='chat-b@example.com' })
    } catch { $offTry = StatusCodeOf $_ }
    Check 'Cam2cam off on either side returns 403'    ($offTry -eq 403) ('got ' + $offTry)

    # Toggle cam2cam on for both peers.
    $c2cOnA = Invoke-RestMethod -Uri ($Base + '/api/cam2cam') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ enabled=$true })
    $c2cOnB = Invoke-RestMethod -Uri ($Base + '/api/cam2cam') -Method Post -ContentType 'application/json' -WebSession $chatB -Body (JsonBody @{ enabled=$true })
    Check 'ChatA cam2cam toggle returns ok'           ($c2cOnA.ok -eq $true -and $c2cOnA.cam2cam -eq $true)
    Check 'ChatB cam2cam toggle returns ok'           ($c2cOnB.ok -eq $true -and $c2cOnB.cam2cam -eq $true)
    Check 'Public-User reflects cam2cam=true'         ($c2cOnA.user.cam2cam -eq $true)

    # Self-call -> 400.
    $selfCall = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/request') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ to='chat-a@example.com' })
    } catch { $selfCall = StatusCodeOf $_ }
    Check 'Calling yourself returns 400'              ($selfCall -eq 400) ('got ' + $selfCall)

    # Unknown peer -> 404.
    $unkCall = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/request') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ to='nope@example.com' })
    } catch { $unkCall = StatusCodeOf $_ }
    Check 'Unknown peer call returns 404'             ($unkCall -eq 404) ('got ' + $unkCall)

    # ChatA requests cam2cam with ChatB.
    $req = Invoke-RestMethod -Uri ($Base + '/api/cam/request') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ to='chat-b@example.com' })
    Check 'Cam request returns ok'                    ($req.ok -eq $true)
    Check 'Cam request returns id'                    ([bool]$req.id)
    Check 'Cam request status pending'                ($req.status -eq 'pending')
    $callId = [string]$req.id

    # ChatB inbox shows the pending request as callee.
    $inboxB = Invoke-RestMethod -Uri ($Base + '/api/cam/inbox') -WebSession $chatB
    $found = $null
    foreach ($c in @($inboxB.calls)) { if ($c.id -eq $callId) { $found = $c; break } }
    Check 'ChatB inbox lists the call'                ($null -ne $found)
    if ($found) {
        Check 'ChatB inbox role is callee'            ($found.role -eq 'callee')
        Check 'ChatB inbox status pending'            ($found.status -eq 'pending')
        Check 'ChatB inbox preserves fromName'        ($found.fromName -eq 'ChatA')
    }

    # Wrong-callee respond -> 403.
    $forbidRespond = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/respond') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ id=$callId; accept=$true })
    } catch { $forbidRespond = StatusCodeOf $_ }
    Check 'Caller cannot respond to own call (403)'   ($forbidRespond -eq 403) ('got ' + $forbidRespond)

    # Cannot signal until accepted.
    $earlySig = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/signal') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ id=$callId; kind='offer'; payload=@{ type='offer'; sdp='v=0' } })
    } catch { $earlySig = StatusCodeOf $_ }
    Check 'Signal before accept returns 409'          ($earlySig -eq 409) ('got ' + $earlySig)

    # ChatB accepts.
    $resp = Invoke-RestMethod -Uri ($Base + '/api/cam/respond') -Method Post -ContentType 'application/json' -WebSession $chatB -Body (JsonBody @{ id=$callId; accept=$true })
    Check 'Respond accept returns ok'                 ($resp.ok -eq $true -and $resp.status -eq 'accepted')

    # ChatA posts SDP offer.
    $sigA1 = Invoke-RestMethod -Uri ($Base + '/api/cam/signal') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ id=$callId; kind='offer'; payload=@{ type='offer'; sdp='v=0' } })
    Check 'ChatA signal offer returns ok'             ($sigA1.ok -eq $true -and $sigA1.seq -eq 1)

    # ChatB pulls signals -- should see ChatA's offer (other side only).
    $pullB = Invoke-RestMethod -Uri ($Base + '/api/cam/signal?id=' + $callId + '&since=0') -WebSession $chatB
    Check 'ChatB receives 1 signal from ChatA'        (@($pullB.signals).Count -eq 1)
    Check 'ChatB sees offer kind'                     (($pullB.signals)[0].kind -eq 'offer')
    Check 'ChatB sees signal status accepted'         ($pullB.status -eq 'accepted')

    # ChatA pulls signals -- should see NONE of its own offer.
    $pullA = Invoke-RestMethod -Uri ($Base + '/api/cam/signal?id=' + $callId + '&since=0') -WebSession $chatA
    Check 'ChatA does not see own signals'            (@($pullA.signals).Count -eq 0)

    # ChatB posts answer + ICE.
    $sigB1 = Invoke-RestMethod -Uri ($Base + '/api/cam/signal') -Method Post -ContentType 'application/json' -WebSession $chatB -Body (JsonBody @{ id=$callId; kind='answer'; payload=@{ type='answer'; sdp='v=0' } })
    Check 'ChatB answer returns seq=2'                ($sigB1.seq -eq 2)
    $sigB2 = Invoke-RestMethod -Uri ($Base + '/api/cam/signal') -Method Post -ContentType 'application/json' -WebSession $chatB -Body (JsonBody @{ id=$callId; kind='ice'; payload=@{ candidate='candidate:1 1 udp 1 1.2.3.4 1234 typ host' } })
    Check 'ChatB ICE returns seq=3'                   ($sigB2.seq -eq 3)

    # ChatA pulls signals -- should see answer + ice (since=1).
    $pullA2 = Invoke-RestMethod -Uri ($Base + '/api/cam/signal?id=' + $callId + '&since=1') -WebSession $chatA
    Check 'ChatA receives answer + ice'               (@($pullA2.signals).Count -eq 2)

    # Stranger cannot read or post signals.
    $strangerSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-RestMethod -Uri ($Base + '/api/register') -Method Post -ContentType 'application/json' -WebSession $strangerSession `
        -Body (JsonBody @{ name='Stranger'; email='stranger@example.com'; password='abcd' })
    $strangerCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/signal?id=' + $callId + '&since=0') -WebSession $strangerSession
    } catch { $strangerCode = StatusCodeOf $_ }
    Check 'Stranger cannot read signals (403)'        ($strangerCode -eq 403) ('got ' + $strangerCode)

    # Bad signal kind -> 400.
    $badKind = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/signal') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ id=$callId; kind='wat'; payload=@{} })
    } catch { $badKind = StatusCodeOf $_ }
    Check 'Bad signal kind returns 400'               ($badKind -eq 400) ('got ' + $badKind)

    # End the call. Subsequent inbox poll shows status='ended'.
    $endRes = Invoke-RestMethod -Uri ($Base + '/api/cam/end') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ id=$callId })
    Check 'Cam end returns ok'                        ($endRes.ok -eq $true -and $endRes.status -eq 'ended')

    $inboxAfter = Invoke-RestMethod -Uri ($Base + '/api/cam/inbox') -WebSession $chatB
    $foundAfter = $null
    foreach ($c in @($inboxAfter.calls)) { if ($c.id -eq $callId) { $foundAfter = $c; break } }
    if ($foundAfter) {
        Check 'Inbox reflects ended status'           ($foundAfter.status -eq 'ended')
    } else {
        # If it has been pruned, that's also acceptable.
        Check 'Ended call removed or marked ended'    $true
    }

    # End on unknown id -> ok with alreadyEnded=true.
    $unkEnd = Invoke-RestMethod -Uri ($Base + '/api/cam/end') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ id='not-a-real-id' })
    Check 'Cam end on unknown id returns ok'          ($unkEnd.ok -eq $true)

    # Cam2cam off bypasses request even if peer is on.
    $null = Invoke-RestMethod -Uri ($Base + '/api/cam2cam') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ enabled=$false })
    $offAfter = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/cam/request') -Method Post -ContentType 'application/json' -WebSession $chatA -Body (JsonBody @{ to='chat-b@example.com' })
    } catch { $offAfter = StatusCodeOf $_ }
    Check 'Caller-side cam2cam off returns 403'       ($offAfter -eq 403) ('got ' + $offAfter)

    # Frontend artifacts.
    Check 'GET /js/camCall.js returns 200'            ((Invoke-WebRequest -Uri ($Base + '/js/camCall.js') -UseBasicParsing).StatusCode -eq 200)
    Check 'cam.html exposes #camOnlineList'           ((Invoke-WebRequest -Uri ($Base + '/cam.html') -UseBasicParsing).Content -match 'id="camOnlineList"')
    Check 'cam.html exposes #camStage'                ((Invoke-WebRequest -Uri ($Base + '/cam.html') -UseBasicParsing).Content -match 'id="camStage"')
    Check 'cam.html exposes #camSideChat'             ((Invoke-WebRequest -Uri ($Base + '/cam.html') -UseBasicParsing).Content -match 'id="camSideChat"')
    Check 'cam.html exposes call controls'            ((Invoke-WebRequest -Uri ($Base + '/cam.html') -UseBasicParsing).Content -match 'id="camEndCall"')
    Check 'styles.css ships .cam-room-grid'           ($cssSrc -match '\.cam-room-grid')
    Check 'styles.css ships .cam-pip'                 ($cssSrc -match '\.cam-pip')

    Section '25. Solana Pay Verification'
    $anonVerifyCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/payments/verify') -Method Post -ContentType 'application/json' -Body (JsonBody @{ signature='mock-sig-xyz' })
    } catch { $anonVerifyCode = StatusCodeOf $_ }
    Check 'Anonymous payment verify returns 401' ($anonVerifyCode -eq 401) ('got ' + $anonVerifyCode)

    $emptySigCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/payments/verify') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body (JsonBody @{ signature='' })
    } catch { $emptySigCode = StatusCodeOf $_ }
    Check 'Empty signature returns 400' ($emptySigCode -eq 400) ('got ' + $emptySigCode)

    $verifyRes = Invoke-RestMethod -Uri ($Base + '/api/payments/verify') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body (JsonBody @{ signature='mock-sig-abc-sol-0.25'; amountSol=0.25 })
    Check 'Mock Solana verify endpoint returns ok' ($verifyRes.ok -eq $true)
    Check 'Mock Solana verify awards expected tokens (2000 per SOL)' ($verifyRes.tokensAwarded -eq 500) ('got ' + $verifyRes.tokensAwarded)
    Check 'Alice tokens updated' ($verifyRes.user.tokens -eq 1000) ('got ' + $verifyRes.user.tokens)

    $doubleSpendCode = 0
    try {
        $null = Invoke-RestMethod -Uri ($Base + '/api/payments/verify') -Method Post -ContentType 'application/json' -WebSession $aliceSession -Body (JsonBody @{ signature='mock-sig-abc-sol-0.25'; amountSol=0.25 })
    } catch { $doubleSpendCode = StatusCodeOf $_ }
    Check 'Double spending signature returns 409 Conflict' ($doubleSpendCode -eq 409) ('got ' + $doubleSpendCode)

    Section '26. Gemini AI Companion Bots'
    $modelsRes = Invoke-RestMethod -Uri ($Base + '/api/models')
    $lunaModel = @($modelsRes.models) | Where-Object { $_.slug -eq 'luna' }
    Check 'Luna AI Companion exists in roster' ($null -ne $lunaModel)
    Check 'Luna accountType is model' ($lunaModel.accountType -eq 'model') ('got ' + $lunaModel.accountType)

    $lunaDetail = Invoke-RestMethod -Uri ($Base + '/api/models/luna') -WebSession $aliceSession
    Check 'Luna details load successfully' ($lunaDetail.model.name -eq 'Luna')

    $lunaSend = Invoke-RestMethod -Uri ($Base + '/api/chat/send') -Method Post -ContentType 'application/json' -WebSession $aliceSession `
        -Body (JsonBody @{ peer='luna@example.com'; text='Hi Luna, tell me about yourself!' })
    Check 'DM send to Luna returned ok' ($lunaSend.ok -eq $true)
    Check 'DM send to Luna returned threadId' ([bool]$lunaSend.threadId)

    # Wait for the async simulated background AI responder to type and persist
    Start-Sleep -Seconds 3

    $lunaMsgs = Invoke-RestMethod -Uri ($Base + '/api/chat/messages?peer=luna@example.com') -WebSession $aliceSession
    $lunaReply = @($lunaMsgs.messages) | Where-Object { $_.from -eq 'luna@example.com' } | Select-Object -First 1
    Check 'Luna sent a background reply' ($null -ne $lunaReply)
    if ($lunaReply) {
        Check 'Luna reply contains text' ($lunaReply.text.Length -gt 0) ('got ' + $lunaReply.text)
    }

    Section '27. Model AI Autoreply Settings & Clone Messaging'
    # Fetch initial config (should be empty or defaults)
    $initAi = Invoke-RestMethod -Uri ($Base + '/api/model/ai-config') -WebSession $modelSess
    Check 'Initial model AI config is empty' ($null -eq $initAi.aiConfig.enabled -or $initAi.aiConfig.enabled -eq $false)

    # Save new config settings
    $saveAi = Invoke-RestMethod -Uri ($Base + '/api/model/ai-config') -Method Post -ContentType 'application/json' -WebSession $modelSess `
        -Body (JsonBody @{ enabled=$true; alwaysOn=$true; cloneName='Cyber Nova'; personality='retro gamer clone' })
    Check 'Save AI config returned ok' ($saveAi.ok -eq $true)
    Check 'AI config enabled is saved' ($saveAi.aiConfig.enabled -eq $true)
    Check 'AI config cloneName is saved' ($saveAi.aiConfig.cloneName -eq 'Cyber Nova')
    Check 'AI config personality is saved' ($saveAi.aiConfig.personality -eq 'retro gamer clone')

    # Send a message to model to trigger the custom-prompted Gemini clone responder
    $novaSend = Invoke-RestMethod -Uri ($Base + '/api/chat/send') -Method Post -ContentType 'application/json' -WebSession $aliceSession `
        -Body (JsonBody @{ peer='nova@example.com'; text='Hi Nova, are you there?' })
    Check 'DM send to model Nova returned ok' ($novaSend.ok -eq $true)

    # Wait for the async simulated background AI responder to respond
    Start-Sleep -Seconds 3

    # Fetch messages and verify the clone replied dynamically
    $novaMsgs = Invoke-RestMethod -Uri ($Base + '/api/chat/messages?peer=nova@example.com') -WebSession $aliceSession
    $novaReply = @($novaMsgs.messages) | Where-Object { $_.from -eq 'nova@example.com' } | Select-Object -First 1
    Check 'Nova AI clone sent a reply' ($null -ne $novaReply)
    if ($novaReply) {
        Check 'Nova reply contains custom cloneName' ($novaReply.text -match 'Cyber Nova') ('got ' + $novaReply.text)
    }

    Section '28. Web3 Supporter Tiers, Glowing Badges, & Redeemable Name Glow'
    # Retrieve Alice's initial tier based on 1000 tokens
    $aliceGold = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $aliceSession
    Check 'Alice computed tier badge is Gold' ($aliceGold.user.badge -eq 'gold') ('got ' + $aliceGold.user.badge)

    # Award Alice another 1000 tokens to cross the 2000 mark (Platinum)
    $platVerify = Invoke-RestMethod -Uri ($Base + '/api/payments/verify') -Method Post -ContentType 'application/json' `
        -WebSession $aliceSession -Body (JsonBody @{ signature='mock-sig-plat-sol-0.5'; amountSol=0.5 })
    Check 'Awarding 1000 tokens succeeds' ($platVerify.tokensAwarded -eq 1000) ('got ' + $platVerify.tokensAwarded)
    Check 'Alice tokens updated to 2000' ($platVerify.user.tokens -eq 2000) ('got ' + $platVerify.user.tokens)
    Check 'Alice computed tier badge updated to Platinum' ($platVerify.user.badge -eq 'platinum') ('got ' + $platVerify.user.badge)

    # Redeem "Premium name glow" (costs 1000 points, Gold tier min)
    # First, make sure Alice has at least 1000 points. Let's adjust her points via the admin endpoint.
    $adjustPoints = Invoke-RestMethod -Uri ($Base + '/api/admin/users/adjust') -Method Post -ContentType 'application/json' `
        -Headers $adminHead -Body (JsonBody @{ email='alice@example.com'; points=1500 })
    Check 'Points adjusted for Alice' ($adjustPoints.user.points -eq 1500) ('got ' + $adjustPoints.user.points)

    $redeemGlow = Invoke-RestMethod -Uri ($Base + '/api/redeem') -Method Post -ContentType 'application/json' `
        -WebSession $aliceSession -Body (JsonBody @{ rewardId='name-glow' })
    Check 'Name glow redemption succeeds' ($null -ne $redeemGlow.redemption)

    # Fetch Alice's details and assert nameGlow is true
    $aliceGlow = Invoke-RestMethod -Uri ($Base + '/api/me') -WebSession $aliceSession
    Check 'Alice nameGlow is now active' ($aliceGlow.user.nameGlow -eq $true)

    Section '29. OBS Stream Overlay HUD Layout Probe'
    # Probe overlay.html with HUD layout
    $hudProbe = Invoke-WebRequest -Uri ($Base + '/overlay.html?layout=hud') -UseBasicParsing
    Check 'overlay.html?layout=hud returns 200' ($hudProbe.StatusCode -eq 200)
    Check 'overlay.html contains goal progress thermometer' ($hudProbe.Content -match 'id="goal-container"')

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
