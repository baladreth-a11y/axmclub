# AxMclub — Rebuild Clean Database
#
# Wipes the SQLite database and initializes it with:
# 1. Core schema
# 2. Three model accounts (Model 1, Model 2, Model 3)
# 3. Default site configuration (Wheel, Tasks, Catalog)
#
# Run this from the project root.

$ErrorActionPreference = 'Stop'
$Root = Get-Item .
$BinDir = Join-Path $Root 'bin'
$DataDir = Join-Path $Root 'data'
$DbSqlite = Join-Path $DataDir 'database.sqlite'

# Load helper functions
. (Join-Path $Root 'db-sqlite.ps1')

# Stop service if running locally (best effort)
try { Stop-Service axmclub -ErrorAction SilentlyContinue } catch {}

# Wipe DB
if (Test-Path $DbSqlite) {
    Remove-Item $DbSqlite -Force
    Write-Host "Wiped existing database." -ForegroundColor Yellow
}

# 1. Initialize Schema
# (Schema creation happens automatically on first query in db-sqlite.ps1, but let's be explicit)
$schema = @"
CREATE TABLE users (
    email TEXT PRIMARY KEY,
    name TEXT,
    pwHash TEXT,
    pwSalt TEXT,
    points INTEGER,
    tokens INTEGER,
    spins INTEGER,
    lastSpinMs INTEGER,
    accountType TEXT,
    joinedMs INTEGER,
    emailVerified INTEGER,
    verifyToken TEXT,
    verifyTokenExpires INTEGER,
    bio TEXT,
    brandColor TEXT,
    gender TEXT,
    rank TEXT,
    gallery TEXT,
    tasks TEXT,
    redemptions TEXT,
    socials TEXT,
    aiConfig TEXT,
    slug TEXT,
    photoUrl TEXT,
    lastSeenMs INTEGER,
    cam2cam INTEGER,
    dmPolicy TEXT
);
CREATE TABLE sessions (
    token TEXT PRIMARY KEY,
    email TEXT,
    createdAt INTEGER
);
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    email_a TEXT,
    email_b TEXT,
    lastMs INTEGER,
    lastRead TEXT,
    messages TEXT
);
CREATE TABLE public_chat (
    id TEXT PRIMARY KEY,
    from_email TEXT,
    name TEXT,
    text TEXT,
    at INTEGER
);
CREATE TABLE feedback (
    id TEXT PRIMARY KEY,
    from_email TEXT,
    text TEXT,
    status TEXT,
    at INTEGER
);
CREATE TABLE stats (
    id INTEGER PRIMARY KEY,
    members INTEGER,
    spins INTEGER,
    offersPending INTEGER,
    offersAccepted INTEGER
);
CREATE TABLE config (
    key TEXT PRIMARY KEY,
    value TEXT
);
"@
Invoke-SqlQuery -query $schema | Out-Null

# 2. Add Stats
Invoke-SqlQuery -query "INSERT INTO stats (id, members, spins, offersPending, offersAccepted) VALUES (1, 3, 0, 0, 0)" | Out-Null

# 3. Add 3 Models
$models = @(
    @{ email='luna@example.com'; name='Luna'; slug='luna'; bio='Your sweet and helpful AI companion. I am always online and ready to chat. Let''s get to know each other!'; brandColor='#00f2fe'; photoUrl='/uploads/models/luna/profile.png'; aiConfig='{"enabled":true,"alwaysOn":true,"cloneName":"Luna","personality":"friendly, welcoming, and suggestively playful"}'; rank='Platinum' }
    @{ email='chloe@axmclub.com'; name='Chloe'; slug='chloe'; bio='Sassy, energetic blonde beauty with a big attitude. I love teasing, gold jewelry, and late night club vibes!'; brandColor='#ff758c'; photoUrl='/uploads/models/chloe/profile.png'; aiConfig='{"enabled":true,"alwaysOn":true,"cloneName":"Chloe","personality":"sassy, confident, energetic, and playful"}'; rank='Gold' }
    @{ email='nova@axmclub.com'; name='Nova'; slug='nova'; bio='Sophisticated and creative dark-haired model. Hosting the Sunday Brunches and late-night lounge sessions.'; brandColor='#a18cd1'; photoUrl='/uploads/models/nova/profile.png'; aiConfig='{"enabled":true,"alwaysOn":true,"cloneName":"Nova","personality":"sophisticated, creative, seductive, and thoughtful"}'; rank='Diamond' }
)

# Helper to hash password
function Get-LocalHash($password, $salt) {
    $iterations = 100000
    $saltBytes = [Convert]::FromBase64String($salt)
    $rfc = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $saltBytes, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $hashBytes = $rfc.GetBytes(32)
    return "${iterations}:${salt}:" + [Convert]::ToBase64String($hashBytes)
}

function New-LocalSalt {
    $bytes = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes)
}

$now = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()

foreach ($m in $models) {
    $salt = New-LocalSalt
    $hash = Get-LocalHash 'axm123' $salt  # Default temporary password
    
    $u = @{
        email = $m.email
        name = $m.name
        pwHash = $hash
        pwSalt = $salt
        points = 0
        tokens = 0
        spins = 0
        lastSpinMs = 0
        accountType = 'model'
        joinedMs = $now
        emailVerified = $true
        verifyToken = ''
        verifyTokenExpires = 0
        bio = $m.bio
        brandColor = $m.brandColor
        gender = 'female'
        rank = $m.rank
        gallery = @()
        tasks = @{}
        redemptions = @()
        socials = @{ telegram=''; snap=''; webcam='' }
        aiConfig = $m.aiConfig | ConvertFrom-Json
        slug = $m.slug
        photoUrl = $m.photoUrl
        lastSeenMs = 0
        cam2cam = 1
        dmPolicy = 'open'
    }
    Save-User $u
    Write-Host "Created Model: $($m.email) (password: axm123)" -ForegroundColor Green
}

# 4. Add Default Config
$wheel = @{
    default = @(
        @{ label='10 pts'; points=10 }
        @{ label='50 pts'; points=50 }
        @{ label='100 pts'; points=100 }
        @{ label='25 pts'; points=25 }
        @{ label='500 pts'; points=500 }
        @{ label='20 pts'; points=20 }
        @{ label='75 pts'; points=75 }
        @{ label='5 pts'; points=5 }
    )
}
$tasks = @(
    @{ id='daily_login'; label='Daily Login'; points=10; cooldownMs=86400000; icon='login' }
    @{ id='watch_model'; label='Watch a Model'; points=25; cooldownMs=3600000; icon='play' }
)
$catalog = @(
    @{ id='pass_10m'; label='10-min Pass'; points=500; description='Unlock all model streams for 10 minutes.'; type='cam_pass' }
)

Invoke-SqlQuery "INSERT INTO config (key, value) VALUES ('WheelVariants', @v)" -parameters @{"@v"=(ConvertTo-Json $wheel -Compress)} | Out-Null
Invoke-SqlQuery "INSERT INTO config (key, value) VALUES ('Tasks', @v)" -parameters @{"@v"=(ConvertTo-Json $tasks -Compress)} | Out-Null
Invoke-SqlQuery "INSERT INTO config (key, value) VALUES ('Catalog', @v)" -parameters @{"@v"=(ConvertTo-Json $catalog -Compress)} | Out-Null

Write-Host "Database rebuild COMPLETE. Clean slate ready." -ForegroundColor Cyan
