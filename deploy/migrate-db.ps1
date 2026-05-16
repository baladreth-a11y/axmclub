$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path (Split-Path -Parent $base) 'bin'
$dataDir = Join-Path (Split-Path -Parent $base) 'data'
$dbJson = Join-Path $dataDir 'db.json'
$dbSqlite = Join-Path $dataDir 'database.sqlite'

# Load SQLite DLL
Add-Type -Path (Join-Path $binDir 'System.Data.SQLite.dll')

if (-not (Test-Path $dbJson)) {
    Write-Host "db.json not found."
    exit
}

$json = Get-Content $dbJson -Raw | ConvertFrom-Json

if (Test-Path $dbSqlite) {
    Remove-Item $dbSqlite -Force
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
        password TEXT,
        points INTEGER,
        tokens INTEGER,
        spins INTEGER,
        lastSpin INTEGER,
        isModel INTEGER,
        createdAt INTEGER,
        rank TEXT,
        cam2cam INTEGER,
        bio TEXT,
        photo TEXT,
        gallery TEXT,
        tasks TEXT,
        redemptions TEXT
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

    # Migrate users
    if ($json.users) {
        Write-Host "Migrating users..."
        foreach ($p in $json.users.psobject.properties) {
            $u = $p.value
            $cmd.CommandText = "INSERT INTO users (email, name, password, points, tokens, spins, lastSpin, isModel, createdAt, rank, cam2cam, bio, photo, gallery, tasks, redemptions) VALUES (@email, @name, @password, @points, @tokens, @spins, @lastSpin, @isModel, @createdAt, @rank, @cam2cam, @bio, @photo, @gallery, @tasks, @redemptions)"
            $cmd.Parameters.Clear()
            $cmd.Parameters.AddWithValue("@email", [string]$u.email) | Out-Null
            $cmd.Parameters.AddWithValue("@name", [string]$u.name) | Out-Null
            $cmd.Parameters.AddWithValue("@password", [string]$u.password) | Out-Null
            $cmd.Parameters.AddWithValue("@points", [int]$u.points) | Out-Null
            $cmd.Parameters.AddWithValue("@tokens", [int]$u.tokens) | Out-Null
            $cmd.Parameters.AddWithValue("@spins", [int]$u.spins) | Out-Null
            $cmd.Parameters.AddWithValue("@lastSpin", [long]$u.lastSpin) | Out-Null
            $cmd.Parameters.AddWithValue("@isModel", $(if ($u.isModel) { 1 } else { 0 })) | Out-Null
            $cmd.Parameters.AddWithValue("@createdAt", [long]$u.createdAt) | Out-Null
            $cmd.Parameters.AddWithValue("@rank", [string]$u.rank) | Out-Null
            $cmd.Parameters.AddWithValue("@cam2cam", $(if ($u.cam2cam) { 1 } else { 0 })) | Out-Null
            $cmd.Parameters.AddWithValue("@bio", [string]$u.bio) | Out-Null
            $cmd.Parameters.AddWithValue("@photo", [string]$u.photo) | Out-Null
            $cmd.Parameters.AddWithValue("@gallery", $(if ($u.gallery) { ConvertTo-Json @($u.gallery) -Compress -Depth 10 } else { "[]" })) | Out-Null
            $cmd.Parameters.AddWithValue("@tasks", $(if ($u.tasks) { ConvertTo-Json $u.tasks -Compress -Depth 10 } else { "{}" })) | Out-Null
            $cmd.Parameters.AddWithValue("@redemptions", $(if ($u.redemptions) { ConvertTo-Json @($u.redemptions) -Compress -Depth 10 } else { "[]" })) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
        }
    }

    # Migrate stats
    if ($json.stats) {
        Write-Host "Migrating stats..."
        $cmd.CommandText = "INSERT INTO stats (id, members, spins, offersPending, offersAccepted) VALUES (1, @members, @spins, @offersPending, @offersAccepted)"
        $cmd.Parameters.Clear()
        $cmd.Parameters.AddWithValue("@members", [int]$json.stats.members) | Out-Null
        $cmd.Parameters.AddWithValue("@spins", [int]$json.stats.spins) | Out-Null
        $cmd.Parameters.AddWithValue("@offersPending", [int]$json.stats.offersPending) | Out-Null
        $cmd.Parameters.AddWithValue("@offersAccepted", [int]$json.stats.offersAccepted) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null
    } else {
        $cmd.CommandText = "INSERT INTO stats (id, members, spins, offersPending, offersAccepted) VALUES (1, 0, 0, 0, 0)"
        $cmd.ExecuteNonQuery() | Out-Null
    }

    Write-Host "Migration complete!"
} finally {
    $conn.Close()
}
