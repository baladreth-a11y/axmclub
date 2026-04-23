<#
  AxMclub.com — PowerShell backend
  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
  Then open http://localhost:5173

  - Uses System.Net.HttpListener (built-in)
  - Persists to .\data\db.json
  - Serves static files (index.html, styles.css, app.js)
  - Cookie sessions, SHA-256 password hashing
#>
param(
  [int]$Port = 5173
)

$ErrorActionPreference = 'Stop'

# ---------- Paths ----------
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root 'data'
$DbPath  = Join-Path $DataDir 'db.json'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory $DataDir | Out-Null }

$Script:DbLock = New-Object object

# ---------- Helpers ----------
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

function Load-Db {
  if (-not (Test-Path $DbPath)) {
    return @{
      users    = @{}
      sessions = @{}
      stats    = @{ members = 0; spins = 0 }
      results  = @()
    }
  }
  try {
    $raw = Get-Content $DbPath -Raw -Encoding UTF8
    if (-not $raw) { return @{ users=@{}; sessions=@{}; stats=@{members=0;spins=0}; results=@() } }
    $obj = $raw | ConvertFrom-Json
    $h = ConvertTo-Hashtable $obj
    if (-not $h.users)    { $h.users    = @{} }
    if (-not $h.sessions) { $h.sessions = @{} }
    if (-not $h.stats)    { $h.stats    = @{ members = 0; spins = 0 } }
    if (-not $h.results)  { $h.results  = @() }
    return $h
  } catch {
    Write-Host "WARN: Could not read db.json, starting fresh. ($_)" -ForegroundColor Yellow
    return @{ users=@{}; sessions=@{}; stats=@{members=0;spins=0}; results=@() }
  }
}

function Save-Db($db) {
  $json = $db | ConvertTo-Json -Depth 20
  $tmp = "$DbPath.tmp"
  [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
  Move-Item -Force $tmp $DbPath
}

function New-Salt {
  $bytes = New-Object byte[] 16
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return [Convert]::ToBase64String($bytes)
}

function Hash-Password($password, $salt) {
  $sha = [Security.Cryptography.SHA256]::Create()
  $bytes = [Text.Encoding]::UTF8.GetBytes("${salt}:${password}")
  return [Convert]::ToBase64String($sha.ComputeHash($bytes))
}

function New-Token { [guid]::NewGuid().ToString('N') }

function NowMs { [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }

# ---------- Domain ----------
$Script:Segments = @(
  @{ label='10 pts';  points=10  },
  @{ label='50 pts';  points=50  },
  @{ label='100 pts'; points=100 },
  @{ label='25 pts';  points=25  },
  @{ label='500 pts'; points=500 },
  @{ label='20 pts';  points=20  },
  @{ label='75 pts';  points=75  },
  @{ label='5 pts';   points=5   }
)
$Script:CooldownMs        = 24 * 60 * 60 * 1000  # 24h
$Script:StreakWindowMs    = 48 * 60 * 60 * 1000  # 48h grace to keep streak alive
$Script:StreakBonusEvery  = 7
$Script:StreakBonusPts    = 100
$Script:CamPassDurationMs = 10 * 60 * 1000       # 10 min

# Cam-room passwords (issued by the model / admin).
# `usesByUser` tracks per-user one-shot redemptions to prevent spam.
$Script:CamPasswords = @{
  'MODEL10'    = @{ uses = 5;   note = 'Model of the day';     usesByUser = @{} }
  'VIP-FAST'   = @{ uses = 10;  note = 'VIP holders';           usesByUser = @{} }
  'OPEN-HOUSE' = @{ uses = 999; note = 'Open house — everyone'; usesByUser = @{} }
}

# Click-to-claim tasks. cooldownMs = 0 means one-time only.
$Script:Tasks = @(
  @{ id='daily-login';      title='Daily check-in';       reward=15; cooldownMs=86400000;   description='Show up every day for a small boost.' }
  @{ id='share-club';       title='Share AxMclub';         reward=30; cooldownMs=86400000;   description='Paste our promo link somewhere public.' }
  @{ id='visit-partner';    title='Visit a partner offer'; reward=25; cooldownMs=86400000;   description='Take a quick look at a partner page.' }
  @{ id='complete-profile'; title='Complete your profile'; reward=50; cooldownMs=0;          description='One-time bonus for filling in your info.' }
  @{ id='refer-friend';     title='Refer a friend';        reward=75; cooldownMs=604800000;  description='Share your referral link with a friend (weekly).' }
)

# Redeemable rewards catalog
$Script:Catalog = @(
  @{
    id='extra-spin'; title='Extra spin token'; cost=250; minTier='Silver'
    effect='reset-cooldown'
    description='Reset your daily spin cooldown so you can spin again right now.'
  }
  @{
    id='mystery-bonus'; title='Mystery bonus'; cost=500; minTier='Silver'
    effect='random-bonus'
    description='Gamble for a random 50-200 pt windfall on top of your balance.'
  }
  @{
    id='monthly-box'; title='Monthly gift box'; cost=1000; minTier='Gold'
    effect='symbolic'
    description='A curated members-only care package.'
  }
  @{
    id='concierge'; title='Concierge consult'; cost=2500; minTier='Platinum'
    effect='symbolic'
    description='Book a 30-minute 1:1 concierge session.'
  }
  @{
    id='cam-pass'; title='10-minute cam pass'; cost=1500; minTier='Gold'
    effect='cam-pass'
    description='Unlock the cam room for 10 minutes immediately.'
  }
)

$Script:TierRanks = @{ Silver = 0; Gold = 1; Platinum = 2 }
function Get-TierRank($name) {
  if ($Script:TierRanks.ContainsKey($name)) { return [int]$Script:TierRanks[$name] }
  return 0
}

function Get-Tier($points) {
  $p = [int]$points
  if ($p -ge 1500) { return @{ name='Platinum'; bonus=0.30 } }
  if ($p -ge 500)  { return @{ name='Gold';     bonus=0.15 } }
  return @{ name='Silver'; bonus=0.0 }
}

function Public-User($u) {
  if (-not $u) { return $null }
  $redCount = 0
  if ($u.redemptions) { $redCount = @($u.redemptions).Count }
  $streak = 0
  if ($u.streak) { $streak = [int]$u.streak }
  $camExp = 0
  if ($u.camPassExpires) { $camExp = [long]$u.camPassExpires }
  $acct = 'supporter'
  if ($u.accountType) { $acct = [string]$u.accountType }
  $tokens = 0
  if ($u.tokens) { $tokens = [int]$u.tokens }
  $rank = ''
  if ($u.rank)   { $rank   = [string]$u.rank }
  $level = [int]$u.points + $tokens
  return @{
    name           = $u.name
    email          = $u.email
    points         = [int]$u.points
    tokens         = $tokens
    rank           = $rank
    level          = $level
    lastSpin       = [long]$u.lastSpin
    joined         = [long]$u.joined
    tier           = (Get-Tier $u.points).name
    streak         = $streak
    redemptions    = $redCount
    camPassExpires = $camExp
    accountType    = $acct
  }
}

# ---------- Response helpers ----------
function Send-Json($resp, $obj, [int]$status = 200, $cookies = @()) {
  $resp.StatusCode = $status
  $resp.ContentType = 'application/json; charset=utf-8'
  foreach ($c in $cookies) { $resp.Headers.Add('Set-Cookie', $c) }
  $json = $obj | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $resp.ContentLength64 = $bytes.Length
  $resp.OutputStream.Write($bytes, 0, $bytes.Length)
  $resp.OutputStream.Close()
}

function Send-Static($resp, $fullPath) {
  if (-not (Test-Path $fullPath) -or (Get-Item $fullPath).PSIsContainer) {
    $resp.StatusCode = 404; $resp.Close(); return
  }
  $ext = [IO.Path]::GetExtension($fullPath).ToLower()
  $mime = switch ($ext) {
    '.html' { 'text/html; charset=utf-8' }
    '.css'  { 'text/css; charset=utf-8' }
    '.js'   { 'application/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.svg'  { 'image/svg+xml' }
    '.png'  { 'image/png' }
    '.ico'  { 'image/x-icon' }
    default { 'application/octet-stream' }
  }
  $bytes = [IO.File]::ReadAllBytes($fullPath)
  $resp.ContentType = $mime
  $resp.ContentLength64 = $bytes.Length
  $resp.OutputStream.Write($bytes, 0, $bytes.Length)
  $resp.OutputStream.Close()
}

function Read-JsonBody($req) {
  if (-not $req.HasEntityBody) { return @{} }
  $reader = New-Object IO.StreamReader($req.InputStream, $req.ContentEncoding)
  $body = $reader.ReadToEnd()
  $reader.Close()
  if ([string]::IsNullOrWhiteSpace($body)) { return @{} }
  try { return ConvertTo-Hashtable ($body | ConvertFrom-Json) } catch { return @{} }
}

function Get-SessionUser($req, $db) {
  $cookie = $req.Cookies['sid']
  if (-not $cookie) { return $null }
  $sid = $cookie.Value
  if (-not $db.sessions.ContainsKey($sid)) { return $null }
  $email = $db.sessions[$sid]
  if (-not $db.users.ContainsKey($email)) { return $null }
  return @{ sid = $sid; user = $db.users[$email] }
}

function Session-Cookie($sid) {
  return "sid=$sid; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000"
}

# ---------- API ----------
function Handle-Api($req, $resp, $path, $method) {
  $db = Load-Db
  $key = "$method $path"

  switch ($key) {

    'POST /api/register' {
      $body = Read-JsonBody $req
      $name = ("$($body.name)").Trim()
      $email = ("$($body.email)").Trim().ToLower()
      $password = "$($body.password)"
      $accountType = ("$($body.accountType)").Trim().ToLower()
      if (-not $accountType) { $accountType = 'supporter' }
      if ($accountType -eq 'model') {
        Send-Json $resp @{ error = 'Model accounts are invite-only and coming soon.' } 403; return
      }
      if ($accountType -ne 'supporter') {
        Send-Json $resp @{ error = 'Invalid account type.' } 400; return
      }
      if (-not $name -or -not $email -or -not $password) {
        Send-Json $resp @{ error = 'Name, email and password are required.' } 400; return
      }
      if ($password.Length -lt 4) {
        Send-Json $resp @{ error = 'Password must be at least 4 characters.' } 400; return
      }
      if ($db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'An account with this email already exists.' } 409; return
      }
      $salt = New-Salt
      $hash = Hash-Password $password $salt
      $db.users[$email] = @{
        name        = $name
        email       = $email
        pwSalt      = $salt
        pwHash      = $hash
        points      = 0
        tokens      = 0
        rank        = ''
        offers      = @()
        lastSpin    = 0
        joined      = NowMs
        accountType = $accountType
      }
      $db.stats.members = [int]$db.stats.members + 1
      $sid = New-Token
      $db.sessions[$sid] = $email
      Save-Db $db
      Send-Json $resp @{ user = (Public-User $db.users[$email]) } 200 @((Session-Cookie $sid))
      return
    }

    'POST /api/login' {
      $body = Read-JsonBody $req
      $email = ("$($body.email)").Trim().ToLower()
      $password = "$($body.password)"
      if (-not $db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'Invalid email or password.' } 401; return
      }
      $u = $db.users[$email]
      if ((Hash-Password $password $u.pwSalt) -ne $u.pwHash) {
        Send-Json $resp @{ error = 'Invalid email or password.' } 401; return
      }
      $sid = New-Token
      $db.sessions[$sid] = $email
      Save-Db $db
      Send-Json $resp @{ user = (Public-User $u) } 200 @((Session-Cookie $sid))
      return
    }

    'POST /api/logout' {
      $s = Get-SessionUser $req $db
      if ($s) { $db.sessions.Remove($s.sid); Save-Db $db }
      $expired = 'sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0'
      Send-Json $resp @{ ok = $true } 200 @($expired)
      return
    }

    'GET /api/me' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ user = $null }; return }
      Send-Json $resp @{ user = (Public-User $s.user) }
      return
    }

    'GET /api/stats' {
      Send-Json $resp @{ members = [int]$db.stats.members; spins = [int]$db.stats.spins }
      return
    }

    'POST /api/spin' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ error = 'Sign in required.' } 401; return }
      $u = $s.user
      $now = NowMs
      $elapsed = $now - [long]$u.lastSpin
      if ([long]$u.lastSpin -gt 0 -and $elapsed -lt $Script:CooldownMs) {
        Send-Json $resp @{ error = 'Spin on cooldown.'; remainingMs = ($Script:CooldownMs - $elapsed) } 429
        return
      }

      # Streak: continuing if last spin was within the streak window; otherwise reset.
      $prevStreak = 0
      if ($u.streak) { $prevStreak = [int]$u.streak }
      $newStreak = 1
      if ([long]$u.lastSpin -gt 0 -and $elapsed -lt $Script:StreakWindowMs) {
        $newStreak = $prevStreak + 1
      }

      $idx = Get-Random -Minimum 0 -Maximum $Script:Segments.Count
      $seg = $Script:Segments[$idx]
      $tier = Get-Tier $u.points
      $tierBonus = [int][math]::Round(([int]$seg.points) * [double]$tier.bonus)
      $streakBonus = 0
      if ($newStreak -gt 0 -and ($newStreak % $Script:StreakBonusEvery) -eq 0) {
        $streakBonus = [int]$Script:StreakBonusPts
      }
      $total = [int]$seg.points + $tierBonus + $streakBonus

      $u.points   = [int]$u.points + $total
      $u.lastSpin = $now
      $u.streak   = $newStreak
      if (-not $u.history) { $u.history = @() }
      $u.history = @($u.history) + @{
        idx         = $idx
        label       = $seg.label
        points      = [int]$seg.points
        bonus       = $tierBonus
        streakBonus = $streakBonus
        streak      = $newStreak
        total       = $total
        at          = $now
      }
      if ($u.history.Count -gt 10) { $u.history = @($u.history[-10..-1]) }

      $db.stats.spins = [int]$db.stats.spins + 1
      $db.results = @($db.results) + @{
        email = $u.email; idx = $idx; points = [int]$seg.points
        bonus = $tierBonus; streakBonus = $streakBonus
        total = $total; at = $now
      }
      if ($db.results.Count -gt 200) { $db.results = @($db.results[-200..-1]) }
      Save-Db $db

      Send-Json $resp @{
        index       = $idx
        label       = $seg.label
        points      = [int]$seg.points
        bonus       = $tierBonus
        streakBonus = $streakBonus
        streak      = $newStreak
        total       = $total
        tier        = $tier.name
        user        = (Public-User $u)
      }
      return
    }

    'GET /api/rewards' {
      $s = Get-SessionUser $req $db
      $u = $null
      if ($s) { $u = $s.user }
      $userPoints = 0
      $userTier   = 'Silver'
      if ($u) {
        $userPoints = [int]$u.points
        $userTier   = (Get-Tier $u.points).name
      }
      $userRank = Get-TierRank $userTier
      $list = @()
      foreach ($r in $Script:Catalog) {
        $tierOk    = ($userRank -ge (Get-TierRank $r.minTier))
        $canAfford = ($userPoints -ge [int]$r.cost)
        $list += @{
          id          = $r.id
          title       = $r.title
          description = $r.description
          cost        = [int]$r.cost
          minTier     = $r.minTier
          effect      = $r.effect
          tierOk      = $tierOk
          canAfford   = $canAfford
          available   = ([bool]$u -and $tierOk -and $canAfford)
        }
      }
      Send-Json $resp @{
        rewards    = @($list)
        userPoints = $userPoints
        userTier   = $userTier
        signedIn   = [bool]$u
      }
      return
    }

    'POST /api/redeem' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ error = 'Sign in required.' } 401; return }
      $u = $s.user
      $body = Read-JsonBody $req
      $rewardId = ("$($body.rewardId)").Trim()
      if (-not $rewardId) {
        Send-Json $resp @{ error = 'rewardId is required.' } 400; return
      }
      $reward = $null
      foreach ($r in $Script:Catalog) { if ($r.id -eq $rewardId) { $reward = $r; break } }
      if (-not $reward) {
        Send-Json $resp @{ error = 'Reward not found.' } 404; return
      }
      $userTier = (Get-Tier $u.points).name
      if ((Get-TierRank $userTier) -lt (Get-TierRank $reward.minTier)) {
        Send-Json $resp @{ error = ('Requires ' + $reward.minTier + ' tier.') } 403; return
      }
      if ([int]$u.points -lt [int]$reward.cost) {
        Send-Json $resp @{ error = 'Not enough points.' } 402; return
      }

      $u.points = [int]$u.points - [int]$reward.cost

      $effectMessage = 'Redeemed.'
      $extraBonus = 0
      switch ($reward.effect) {
        'reset-cooldown' {
          $u.lastSpin = 0
          $effectMessage = 'Your daily spin is ready again.'
        }
        'random-bonus' {
          $extraBonus = Get-Random -Minimum 50 -Maximum 201
          $u.points = [int]$u.points + $extraBonus
          $effectMessage = ('You uncovered ' + $extraBonus + ' bonus pts.')
        }
        'cam-pass' {
          $u.camPassExpires = (NowMs) + $Script:CamPassDurationMs
          $effectMessage = 'Cam room unlocked for 10 minutes. Enjoy!'
        }
        default {
          $effectMessage = 'Claim recorded. Our team will be in touch.'
        }
      }

      if (-not $u.redemptions) { $u.redemptions = @() }
      $redemption = @{
        id         = (New-Token)
        rewardId   = $reward.id
        title      = $reward.title
        cost       = [int]$reward.cost
        effect     = $reward.effect
        message    = $effectMessage
        extraBonus = $extraBonus
        at         = (NowMs)
      }
      $u.redemptions = @($u.redemptions) + $redemption
      if ($u.redemptions.Count -gt 20) { $u.redemptions = @($u.redemptions[-20..-1]) }
      Save-Db $db

      Send-Json $resp @{
        redemption = $redemption
        user       = (Public-User $u)
      }
      return
    }

    'GET /api/redemptions' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ redemptions = @() }; return }
      $r = $s.user.redemptions
      if (-not $r) { $r = @() }
      Send-Json $resp @{ redemptions = @($r) }
      return
    }

    'GET /api/history' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ history = @() }; return }
      $h = $s.user.history
      if (-not $h) { $h = @() }
      Send-Json $resp @{ history = @($h) }
      return
    }

    'POST /api/tokens/buy' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ error = 'Sign in required.' } 401; return }
      $u = $s.user
      $body = Read-JsonBody $req
      $amount = 0
      if ($body.amount) { $amount = [int]$body.amount }
      # Accept a small set of preset packs only (demo mode — no real payment).
      $allowed = @(100, 500, 1200, 3000)
      if ($allowed -notcontains $amount) {
        Send-Json $resp @{ error = 'Invalid pack size.' } 400; return
      }
      if (-not $u.tokens) { $u.tokens = 0 }
      $u.tokens = [int]$u.tokens + $amount
      Save-Db $db
      Send-Json $resp @{
        ok     = $true
        bought = $amount
        user   = (Public-User $u)
      }
      return
    }

    'POST /api/offer' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ error = 'Sign in required.' } 401; return }
      $u = $s.user
      $body = Read-JsonBody $req
      $target  = ("$($body.target)").Trim()
      $message = ("$($body.message)").Trim()
      if (-not $message -or $message.Length -lt 10) {
        Send-Json $resp @{ error = 'Offer must be at least 10 characters.' } 400; return
      }
      if (-not $u.offers) { $u.offers = @() }
      $offer = @{
        id      = (New-Token)
        target  = $target
        message = $message
        at      = (NowMs)
        status  = 'pending'
      }
      $u.offers = @($u.offers) + $offer
      if ($u.offers.Count -gt 20) { $u.offers = @($u.offers[-20..-1]) }
      Save-Db $db
      Send-Json $resp @{ ok = $true; offer = $offer }
      return
    }

    'GET /api/cam/status' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ error = 'Sign in required.' } 401; return }
      $u = $s.user
      $now = NowMs
      $exp = [long]0
      if ($u.camPassExpires) { $exp = [long]$u.camPassExpires }
      # Force the Int64 overload of Math.Max (unix ms always overflows Int32).
      $remaining = [math]::Max([long]0, [long]($exp - $now))
      Send-Json $resp @{
        active      = ($remaining -gt 0)
        expiresAt   = $exp
        remainingMs = $remaining
      }
      return
    }

    'POST /api/cam/redeem-password' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ error = 'Sign in required.' } 401; return }
      $u = $s.user
      $body = Read-JsonBody $req
      $pw = ("$($body.password)").Trim().ToUpper()
      if (-not $pw) {
        Send-Json $resp @{ error = 'Password is required.' } 400; return
      }
      if (-not $Script:CamPasswords.ContainsKey($pw)) {
        Send-Json $resp @{ error = 'Invalid password.' } 404; return
      }
      $entry = $Script:CamPasswords[$pw]
      if (-not $entry.usesByUser) { $entry.usesByUser = @{} }
      if ($entry.usesByUser.ContainsKey($u.email)) {
        Send-Json $resp @{ error = 'You already redeemed this password.' } 409; return
      }
      if ([int]$entry.uses -le 0) {
        Send-Json $resp @{ error = 'Password has been used up.' } 410; return
      }
      $entry.uses = [int]$entry.uses - 1
      $entry.usesByUser[$u.email] = (NowMs)
      $u.camPassExpires = (NowMs) + $Script:CamPassDurationMs
      Save-Db $db
      Send-Json $resp @{
        ok             = $true
        note           = $entry.note
        camPassExpires = [long]$u.camPassExpires
        remainingMs    = $Script:CamPassDurationMs
        user           = (Public-User $u)
      }
      return
    }

    'POST /api/cam/create-password' {
      $adminKey = $env:AURUM_ADMIN_KEY
      $given = $req.Headers['x-admin-key']
      if (-not $adminKey -or $given -ne $adminKey) {
        Send-Json $resp @{ error = 'Admin only.' } 403; return
      }
      $body = Read-JsonBody $req
      $pw = ("$($body.password)").Trim().ToUpper()
      $uses = 1
      if ($body.uses) { $uses = [int]$body.uses }
      if (-not $pw) { Send-Json $resp @{ error = 'password is required.' } 400; return }
      $Script:CamPasswords[$pw] = @{ uses = $uses; note = 'Admin-issued'; usesByUser = @{} }
      Send-Json $resp @{ ok = $true; password = $pw; uses = $uses }
      return
    }

    'GET /api/tasks' {
      $s = Get-SessionUser $req $db
      $u = $null
      if ($s) { $u = $s.user }
      $claims = @{}
      if ($u -and $u.taskClaims) { $claims = $u.taskClaims }
      $now = NowMs
      $list = @()
      foreach ($t in $Script:Tasks) {
        $claimedAt = 0
        if ($claims.ContainsKey($t.id)) { $claimedAt = [long]$claims[$t.id] }
        $available = $true
        $cooldownRemaining = 0
        if ($claimedAt -gt 0) {
          if ([long]$t.cooldownMs -eq 0) {
            $available = $false
          }
          else {
            $elapsed = $now - $claimedAt
            if ($elapsed -lt [long]$t.cooldownMs) {
              $available = $false
              $cooldownRemaining = [long]$t.cooldownMs - $elapsed
            }
          }
        }
        $list += @{
          id                = $t.id
          title             = $t.title
          description       = $t.description
          reward            = [int]$t.reward
          cooldownMs        = [long]$t.cooldownMs
          claimedAt         = $claimedAt
          available         = ([bool]$u -and $available)
          cooldownRemaining = $cooldownRemaining
        }
      }
      Send-Json $resp @{ tasks = @($list); signedIn = [bool]$u }
      return
    }

    'POST /api/tasks/claim' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ error = 'Sign in required.' } 401; return }
      $u = $s.user
      $body = Read-JsonBody $req
      $id = ("$($body.taskId)").Trim()
      if (-not $id) { Send-Json $resp @{ error = 'taskId is required.' } 400; return }
      $task = $null
      foreach ($t in $Script:Tasks) { if ($t.id -eq $id) { $task = $t; break } }
      if (-not $task) { Send-Json $resp @{ error = 'Task not found.' } 404; return }

      if (-not $u.taskClaims) { $u.taskClaims = @{} }
      $now = NowMs
      if ($u.taskClaims.ContainsKey($task.id)) {
        $prev = [long]$u.taskClaims[$task.id]
        if ([long]$task.cooldownMs -eq 0) {
          Send-Json $resp @{ error = 'One-time task already claimed.' } 409; return
        }
        $elapsed = $now - $prev
        if ($elapsed -lt [long]$task.cooldownMs) {
          Send-Json $resp @{ error = 'Task on cooldown.'; remainingMs = ([long]$task.cooldownMs - $elapsed) } 429; return
        }
      }
      $u.taskClaims[$task.id] = $now
      $u.points = [int]$u.points + [int]$task.reward
      Save-Db $db
      Send-Json $resp @{
        ok       = $true
        taskId   = $task.id
        title    = $task.title
        reward   = [int]$task.reward
        claimedAt = $now
        user     = (Public-User $u)
      }
      return
    }

    'GET /api/leaderboard' {
      $arr = @()
      foreach ($email in $db.users.Keys) {
        $u = $db.users[$email]
        $arr += @{ name = $u.name; points = [int]$u.points; tier = (Get-Tier $u.points).name }
      }
      # NOTE: Sort-Object -Property on an array of hashtables is unreliable
      # in PS 5.1 (may silently fall back to input order). A scriptblock key
      # forces proper numeric comparison.
      $top = $arr | Sort-Object -Property { [int]$_.points } -Descending | Select-Object -First 10
      Send-Json $resp @{ leaderboard = @($top) }
      return
    }

    default {
      Send-Json $resp @{ error = 'Not found.' } 404
    }
  }
}

# ---------- Dispatcher ----------
function Handle-Request($ctx) {
  $req  = $ctx.Request
  $resp = $ctx.Response
  $path = $req.Url.AbsolutePath
  $method = $req.HttpMethod.ToUpper()

  $origin = $req.Headers['Origin']; if (-not $origin) { $origin = '*' }
  $resp.Headers.Add('Access-Control-Allow-Origin',  $origin)
  $resp.Headers.Add('Access-Control-Allow-Credentials', 'true')
  $resp.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  $resp.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')

  if ($method -eq 'OPTIONS') { $resp.StatusCode = 204; $resp.Close(); return }

  try {
    if ($path -like '/api/*') {
      [Threading.Monitor]::Enter($Script:DbLock)
      try { Handle-Api $req $resp $path $method }
      finally { [Threading.Monitor]::Exit($Script:DbLock) }
    } else {
      $rel = if ($path -eq '/' -or [string]::IsNullOrEmpty($path)) { 'index.html' } else { $path.TrimStart('/') }
      $full = [IO.Path]::GetFullPath((Join-Path $Root $rel))
      if (-not $full.StartsWith([IO.Path]::GetFullPath($Root))) {
        $resp.StatusCode = 403; $resp.Close(); return
      }
      if ($full -ieq [IO.Path]::GetFullPath($DbPath)) {
        $resp.StatusCode = 403; $resp.Close(); return
      }
      Send-Static $resp $full
    }
  } catch {
    Write-Host "ERROR handling $method $path :: $_" -ForegroundColor Red
    try { Send-Json $resp @{ error = $_.ToString() } 500 } catch {}
  }
}

# ---------- Start listener ----------
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
try { $listener.Start() }
catch {
  Write-Host "Could not bind to $prefix." -ForegroundColor Red
  Write-Host "Try a different port:  powershell -File .\server.ps1 -Port 8080" -ForegroundColor Yellow
  throw
}

Write-Host ""
Write-Host "  AxMclub.com backend running" -ForegroundColor Green
Write-Host "  -> $prefix" -ForegroundColor Cyan
Write-Host "  -> DB file: $DbPath" -ForegroundColor DarkGray
Write-Host "  Press Ctrl+C to stop."
Write-Host ""

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    Handle-Request $ctx
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
