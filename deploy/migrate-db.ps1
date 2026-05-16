$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $base
$binDir = Join-Path $Root 'bin'
$dataDir = Join-Path $Root 'data'
$dbJson = Join-Path $dataDir 'db.json'
$dbSqlite = Join-Path $dataDir 'database.sqlite'

# Load SQLite DLL
Add-Type -Path (Join-Path $binDir 'System.Data.SQLite.dll')

if (-not (Test-Path $dbJson)) {
    Write-Host "db.json not found. Nothing to migrate." -ForegroundColor Yellow
    exit
}

$json = Get-Content $dbJson -Raw | ConvertFrom-Json

# Helper to hash legacy passwords
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

if (Test-Path $dbSqlite) {
    Remove-Item $dbSqlite -Force
    Write-Host "Wiped old database for clean migration." -ForegroundColor Cyan
}

$connStr = "Data Source=$dbSqlite;Version=3;"
$conn = New-Object System.Data.SQLite.SQLiteConnection $connStr
$conn.Open()

try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = @"
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
        socials TEXT
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
    $cmd.ExecuteNonQuery() | Out-Null

    # Migrate users (KEEP ONLY MODELS)
    if ($json.users) {
        Write-Host "Scanning users..." -ForegroundColor Gray
        $count = 0
        foreach ($p in $json.users.psobject.properties) {
            $u = $p.value
            $acct = 'supporter'
            if ($u.accountType) { $acct = [string]$u.accountType }
            
            # Erase supporters, keep models
            if ($acct -ne 'model') { continue }

            $hash = $u.pwHash
            $salt = $u.pwSalt
            if (-not $hash -and $u.password) {
                # Legacy plain-text password detected, hash it now
                $salt = New-LocalSalt
                $hash = Get-LocalHash $u.password $salt
            }

            $q = "INSERT INTO users (email, name, pwHash, pwSalt, points, tokens, spins, lastSpinMs, accountType, joinedMs, emailVerified, verifyToken, verifyTokenExpires, bio, brandColor, gender, rank, gallery, tasks, redemptions, socials) 
                  VALUES (@email, @name, @pwHash, @pwSalt, @points, @tokens, @spins, @lastSpinMs, @accountType, @joinedMs, @emailVerified, @verifyToken, @verifyTokenExpires, @bio, @brandColor, @gender, @rank, @gallery, @tasks, @redemptions, @socials)"
            $cmd.CommandText = $q
            $cmd.Parameters.Clear()
            $cmd.Parameters.AddWithValue("@email", [string]$u.email) | Out-Null
            $cmd.Parameters.AddWithValue("@name", [string]$u.name) | Out-Null
            $cmd.Parameters.AddWithValue("@pwHash", [string]$hash) | Out-Null
            $cmd.Parameters.AddWithValue("@pwSalt", [string]$salt) | Out-Null
            $cmd.Parameters.AddWithValue("@points", [int]$u.points) | Out-Null
            $cmd.Parameters.AddWithValue("@tokens", [int]$u.tokens) | Out-Null
            $cmd.Parameters.AddWithValue("@spins", [int]$u.spins) | Out-Null
            $cmd.Parameters.AddWithValue("@lastSpinMs", [long]$u.lastSpinMs) | Out-Null
            $cmd.Parameters.AddWithValue("@accountType", 'model') | Out-Null
            $cmd.Parameters.AddWithValue("@joinedMs", [long]$u.joinedMs) | Out-Null
            $cmd.Parameters.AddWithValue("@emailVerified", $(if ($u.emailVerified) { 1 } else { 0 })) | Out-Null
            $cmd.Parameters.AddWithValue("@verifyToken", [string]$u.verifyToken) | Out-Null
            $cmd.Parameters.AddWithValue("@verifyTokenExpires", [long]$u.verifyTokenExpires) | Out-Null
            $cmd.Parameters.AddWithValue("@bio", [string]$u.bio) | Out-Null
            $cmd.Parameters.AddWithValue("@brandColor", [string]$u.brandColor) | Out-Null
            $cmd.Parameters.AddWithValue("@gender", [string]$u.gender) | Out-Null
            $cmd.Parameters.AddWithValue("@rank", [string]$u.rank) | Out-Null
            $cmd.Parameters.AddWithValue("@gallery", $(if ($u.gallery) { ConvertTo-Json @($u.gallery) -Compress } else { "[]" })) | Out-Null
            $cmd.Parameters.AddWithValue("@tasks", $(if ($u.tasks) { ConvertTo-Json $u.tasks -Compress } else { "{}" })) | Out-Null
            $cmd.Parameters.AddWithValue("@redemptions", $(if ($u.redemptions) { ConvertTo-Json @($u.redemptions) -Compress } else { "[]" })) | Out-Null
            $cmd.Parameters.AddWithValue("@socials", $(if ($u.socials) { ConvertTo-Json $u.socials -Compress } else { "{}" })) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
            $count++
            Write-Host "  Migrated Model: $($u.email)" -ForegroundColor Green
        }
        Write-Host "Total Models Migrated: $count" -ForegroundColor Cyan
    }

    # Migrate stats
    $members = 0
    if ($json.stats) { $members = [int]$json.stats.members }
    $cmd.CommandText = "INSERT INTO stats (id, members, spins, offersPending, offersAccepted) VALUES (1, @members, 0, 0, 0)"
    $cmd.Parameters.Clear()
    $cmd.Parameters.AddWithValue("@members", $members) | Out-Null
    $cmd.ExecuteNonQuery() | Out-Null

    # Migrate Config if present
    if ($json.config) {
        foreach ($p in $json.config.psobject.properties) {
            $cmd.CommandText = "INSERT INTO config (key, value) VALUES (@k, @v)"
            $cmd.Parameters.Clear()
            $cmd.Parameters.AddWithValue("@k", $p.name) | Out-Null
            $cmd.Parameters.AddWithValue("@v", (ConvertTo-Json $p.value -Compress)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
        }
    }

    Write-Host "CLEAN MIGRATION COMPLETE. Supporters erased, Models preserved." -ForegroundColor Cyan
} finally {
    $conn.Close()
}
