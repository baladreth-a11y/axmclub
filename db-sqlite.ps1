$Script:SqliteConn = $null
$Script:SqlitePath = Join-Path $DataDir 'database.sqlite'

function Initialize-DatabaseSchema {
    $schema = @"
CREATE TABLE IF NOT EXISTS users (
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
CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    email TEXT,
    createdAt INTEGER
);
CREATE TABLE IF NOT EXISTS threads (
    id TEXT PRIMARY KEY,
    email_a TEXT,
    email_b TEXT,
    lastMs INTEGER,
    lastRead TEXT,
    messages TEXT
);
CREATE TABLE IF NOT EXISTS public_chat (
    id TEXT PRIMARY KEY,
    from_email TEXT,
    name TEXT,
    text TEXT,
    at INTEGER
);
CREATE TABLE IF NOT EXISTS feedback (
    id TEXT PRIMARY KEY,
    from_email TEXT,
    text TEXT,
    status TEXT,
    at INTEGER
);
CREATE TABLE IF NOT EXISTS stats (
    id INTEGER PRIMARY KEY,
    members INTEGER,
    spins INTEGER,
    offersPending INTEGER,
    offersAccepted INTEGER,
    visits INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
);
"@
    $cmd = $Script:SqliteConn.CreateCommand()
    $cmd.CommandText = $schema
    $cmd.ExecuteNonQuery() | Out-Null

    # Dynamic Column Migration check: Ensure existing SQLite files get all required columns
    $colsCmd = $Script:SqliteConn.CreateCommand()
    $colsCmd.CommandText = "PRAGMA table_info(users)"
    $reader = $colsCmd.ExecuteReader()
    $existingCols = @{}
    while ($reader.Read()) {
        $existingCols[$reader.GetValue(1).ToLowerInvariant()] = $true
    }
    $reader.Close()

    $requiredCols = @{
        "aiconfig"   = "TEXT"
        "slug"       = "TEXT"
        "photourl"   = "TEXT"
        "lastseenms" = "INTEGER"
        "cam2cam"    = "INTEGER"
        "dmpolicy"   = "TEXT"
    }

    foreach ($col in $requiredCols.Keys) {
        if (-not $existingCols.ContainsKey($col)) {
            $colType = $requiredCols[$col]
            $alterCmd = $Script:SqliteConn.CreateCommand()
            $alterCmd.CommandText = "ALTER TABLE users ADD COLUMN $col $colType"
            $alterCmd.ExecuteNonQuery() | Out-Null
            Write-Host "Migrated users table: Added column $col" -ForegroundColor Cyan
        }
    }

    # Verify stats table has the visits column
    $statsColsCmd = $Script:SqliteConn.CreateCommand()
    $statsColsCmd.CommandText = "PRAGMA table_info(stats)"
    $reader = $statsColsCmd.ExecuteReader()
    $statsCols = @{}
    while ($reader.Read()) {
        $statsCols[$reader.GetValue(1).ToLowerInvariant()] = $true
    }
    $reader.Close()

    if (-not $statsCols.ContainsKey("visits")) {
        $alterCmd = $Script:SqliteConn.CreateCommand()
        $alterCmd.CommandText = "ALTER TABLE stats ADD COLUMN visits INTEGER DEFAULT 0"
        $alterCmd.ExecuteNonQuery() | Out-Null
        Write-Host "Migrated stats table: Added column visits" -ForegroundColor Cyan
    }

    # Now that all tables and columns are guaranteed to exist, execute seeds safely!
    $seedCmd = $Script:SqliteConn.CreateCommand()
    $seedCmd.CommandText = @"
INSERT OR IGNORE INTO stats (id, members, spins, offersPending, offersAccepted, visits) VALUES (1, 0, 0, 0, 0, 0);
INSERT OR IGNORE INTO users (email, name, pwHash, pwSalt, points, tokens, spins, lastSpinMs, accountType, joinedMs, emailVerified, verifyToken, verifyTokenExpires, bio, brandColor, gender, rank, gallery, tasks, redemptions, socials, aiConfig, slug, photoUrl, lastSeenMs, cam2cam, dmPolicy) 
VALUES ('luna@example.com', 'Luna', '', '', 0, 0, 0, 0, 'model', 1700000000000, 1, '', 0, 'Your sweet and helpful AI companion. I am always online and ready to chat. Let''s get to know each other!', '#00f2fe', 'female', 'Platinum', '[]', '{}', '[]', '{}', '{"enabled":true,"alwaysOn":true,"cloneName":"Luna","personality":"friendly, welcoming, and suggestively playful"}', 'luna', '/uploads/models/luna/profile.png', 0, 1, 'open');
INSERT OR IGNORE INTO users (email, name, pwHash, pwSalt, points, tokens, spins, lastSpinMs, accountType, joinedMs, emailVerified, verifyToken, verifyTokenExpires, bio, brandColor, gender, rank, gallery, tasks, redemptions, socials, aiConfig, slug, photoUrl, lastSeenMs, cam2cam, dmPolicy) 
VALUES ('chloe@axmclub.com', 'Chloe', '', '', 0, 0, 0, 0, 'model', 1700000000000, 1, '', 0, 'Sassy, energetic blonde beauty with a big attitude. I love teasing, gold jewelry, and late night club vibes!', '#ff758c', 'female', 'Gold', '[]', '{}', '[]', '{}', '{"enabled":true,"alwaysOn":true,"cloneName":"Chloe","personality":"sassy, confident, energetic, and playful"}', 'chloe', '/uploads/models/chloe/profile.png', 0, 1, 'open');
INSERT OR IGNORE INTO users (email, name, pwHash, pwSalt, points, tokens, spins, lastSpinMs, accountType, joinedMs, emailVerified, verifyToken, verifyTokenExpires, bio, brandColor, gender, rank, gallery, tasks, redemptions, socials, aiConfig, slug, photoUrl, lastSeenMs, cam2cam, dmPolicy) 
VALUES ('nova@axmclub.com', 'Nova', '', '', 0, 0, 0, 0, 'model', 1700000000000, 1, '', 0, 'Sophisticated and creative dark-haired model. Hosting the Sunday Brunches and late-night lounge sessions.', '#a18cd1', 'female', 'Diamond', '[]', '{}', '[]', '{}', '{"enabled":true,"alwaysOn":true,"cloneName":"Nova","personality":"sophisticated, creative, seductive, and thoughtful"}', 'nova', '/uploads/models/nova/profile.png', 0, 1, 'open');
"@
    $seedCmd.ExecuteNonQuery() | Out-Null

    # Force update profile photos & details for existings
    $updCmd = $Script:SqliteConn.CreateCommand()
    $updCmd.CommandText = @"
UPDATE users SET photoUrl = '/uploads/models/luna/profile.png', slug = 'luna', brandColor = '#00f2fe' WHERE email = 'luna@example.com' AND (photoUrl IS NULL OR photoUrl = '' OR slug IS NULL OR slug = '');
UPDATE users SET photoUrl = '/uploads/models/chloe/profile.png', slug = 'chloe', brandColor = '#ff758c' WHERE email = 'chloe@axmclub.com' AND (photoUrl IS NULL OR photoUrl = '' OR slug IS NULL OR slug = '');
UPDATE users SET photoUrl = '/uploads/models/nova/profile.png', slug = 'nova', brandColor = '#a18cd1' WHERE email = 'nova@axmclub.com' AND (photoUrl IS NULL OR photoUrl = '' OR slug IS NULL OR slug = '');
UPDATE users SET accountType = 'model', aiConfig = '{"enabled":true,"alwaysOn":true,"cloneName":"Luna","personality":"friendly, welcoming, and suggestively playful"}' WHERE email = 'luna@example.com' AND (accountType = 'ai' OR aiConfig IS NULL OR aiConfig = '{}');
UPDATE users SET accountType = 'model', aiConfig = '{"enabled":true,"alwaysOn":true,"cloneName":"Chloe","personality":"sassy, confident, energetic, and playful"}' WHERE email = 'chloe@axmclub.com' AND (accountType = 'ai' OR aiConfig IS NULL OR aiConfig = '{}');
UPDATE users SET accountType = 'model', aiConfig = '{"enabled":true,"alwaysOn":true,"cloneName":"Nova","personality":"sophisticated, creative, seductive, and thoughtful"}' WHERE email = 'nova@axmclub.com' AND (accountType = 'ai' OR aiConfig IS NULL OR aiConfig = '{}');
"@
    $updCmd.ExecuteNonQuery() | Out-Null
}

function Open-DbConnection {
    if ($Script:SqliteConn -and $Script:SqliteConn.State -eq 'Open') { return }
    $binDir = Join-Path $Root 'bin'
    Add-Type -Path (Join-Path $binDir 'System.Data.SQLite.dll') -ErrorAction SilentlyContinue
    
    $connStr = "Data Source=$Script:SqlitePath;Version=3;"
    $Script:SqliteConn = New-Object System.Data.SQLite.SQLiteConnection $connStr
    $Script:SqliteConn.Open()

    # Enable WAL mode for better concurrency
    $cmd = $Script:SqliteConn.CreateCommand()
    $cmd.CommandText = "PRAGMA journal_mode=WAL;"
    $cmd.ExecuteNonQuery() | Out-Null

    # Ensure schema exists
    Initialize-DatabaseSchema
}

function Invoke-SqlQuery($query, $parameters = @{}) {
    Open-DbConnection
    $cmd = $Script:SqliteConn.CreateCommand()
    $cmd.CommandText = $query
    foreach ($k in $parameters.Keys) {
        $cmd.Parameters.AddWithValue($k, $parameters[$k]) | Out-Null
    }
    
    if ($query.TrimStart().StartsWith("SELECT", $true, $null)) {
        $reader = $cmd.ExecuteReader()
        $results = @()
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $row[$reader.GetName($i)] = $reader.GetValue($i)
            }
            $results += New-Object PSObject -Property $row
        }
        $reader.Close()
        return $results
    } else {
        return $cmd.ExecuteNonQuery()
    }
}

function Map-User($r) {
    if (-not $r) { return $null }
    $emailLc = ($r.email).ToLowerInvariant()
    $u = @{
        email         = $emailLc
        name          = if ($r.name -is [System.DBNull]) { $null } else { $r.name }
        pwHash        = if ($r.pwHash -is [System.DBNull]) { $null } else { $r.pwHash }
        pwSalt        = if ($r.pwSalt -is [System.DBNull]) { $null } else { $r.pwSalt }
        points        = [int]$r.points
        tokens        = [int]$r.tokens
        spins         = [int]$r.spins
        lastSpinMs    = [long]$r.lastSpinMs
        lastSpin      = [long]$r.lastSpinMs
        accountType   = if ($r.accountType -is [System.DBNull]) { 'supporter' } else { $r.accountType }
        joinedMs      = [long]$r.joinedMs
        joined        = [long]$r.joinedMs
        emailVerified = [bool]$r.emailVerified
        verifyToken   = if ($r.verifyToken -is [System.DBNull]) { $null } else { $r.verifyToken }
        verifyTokenExpires = [long]$r.verifyTokenExpires
        bio           = if ($r.bio -is [System.DBNull]) { '' } else { $r.bio }
        brandColor    = if ($r.brandColor -is [System.DBNull]) { '' } else { $r.brandColor }
        gender        = if ($r.gender -is [System.DBNull]) { '' } else { $r.gender }
        rank          = if ($r.rank -is [System.DBNull]) { '' } else { $r.rank }
        gallery       = if ($r.gallery -is [System.DBNull]) { @() } else { $r.gallery | ConvertFrom-Json | ConvertTo-Hashtable }
        tasks         = if ($r.tasks -is [System.DBNull]) { @{} } else { $r.tasks | ConvertFrom-Json | ConvertTo-Hashtable }
        redemptions   = if ($r.redemptions -is [System.DBNull]) { @() } else { $r.redemptions | ConvertFrom-Json | ConvertTo-Hashtable }
        socials       = if ($r.socials -is [System.DBNull]) { @{} } else { $r.socials | ConvertFrom-Json | ConvertTo-Hashtable }
        aiConfig      = if ($r.aiConfig -is [System.DBNull]) { @{} } else { $r.aiConfig | ConvertFrom-Json | ConvertTo-Hashtable }
        slug          = if ($r.slug -is [System.DBNull]) { '' } else { $r.slug }
        photoUrl      = if ($r.photoUrl -is [System.DBNull]) { '' } else { $r.photoUrl }
        lastSeenMs    = if ($r.lastSeenMs -is [System.DBNull]) { 0 } else { [long]$r.lastSeenMs }
        cam2cam       = if ($r.cam2cam -is [System.DBNull]) { $false } else { [bool]$r.cam2cam }
        dmPolicy      = if ($r.dmPolicy -is [System.DBNull]) { 'open' } else { $r.dmPolicy }
    }
    return $u
}

function Get-User($email) {
    if (-not $email) { return $null }
    $emailLc = $email.ToLowerInvariant()
    $rows = Invoke-SqlQuery -query "SELECT * FROM users WHERE email = @email" -parameters @{"@email" = $emailLc}
    if (-not $rows) { return $null }
    return Map-User $rows[0]
}

function Save-User($u) {
    $q = "INSERT OR REPLACE INTO users (email, name, pwHash, pwSalt, points, tokens, spins, lastSpinMs, accountType, joinedMs, emailVerified, verifyToken, verifyTokenExpires, bio, brandColor, gender, rank, gallery, tasks, redemptions, socials, aiConfig, slug, photoUrl, lastSeenMs, cam2cam, dmPolicy) 
          VALUES (@email, @name, @pwHash, @pwSalt, @points, @tokens, @spins, @lastSpinMs, @accountType, @joinedMs, @emailVerified, @verifyToken, @verifyTokenExpires, @bio, @brandColor, @gender, @rank, @gallery, @tasks, @redemptions, @socials, @aiConfig, @slug, @photoUrl, @lastSeenMs, @cam2cam, @dmPolicy)"
    
    $params = @{
        "@email"         = [string]$u.email.ToLowerInvariant()
        "@name"          = [string]$u.name
        "@pwHash"        = [string]$u.pwHash
        "@pwSalt"        = [string]$u.pwSalt
        "@points"        = [int]$u.points
        "@tokens"        = [int]$u.tokens
        "@spins"         = [int]$u.spins
        "@lastSpinMs"    = $(if ($null -ne $u.lastSpinMs) { [long]$u.lastSpinMs } elseif ($null -ne $u.lastSpin) { [long]$u.lastSpin } else { 0 })
        "@accountType"   = [string]$u.accountType
        "@joinedMs"      = $(if ($null -ne $u.joinedMs) { [long]$u.joinedMs } elseif ($null -ne $u.joined) { [long]$u.joined } else { 0 })
        "@emailVerified" = [int]$(if ($u.emailVerified) { 1 } else { 0 })
        "@verifyToken"   = [string]$u.verifyToken
        "@verifyTokenExpires" = [long]$u.verifyTokenExpires
        "@bio"           = [string]$u.bio
        "@brandColor"    = [string]$u.brandColor
        "@gender"        = [string]$u.gender
        "@rank"          = [string]$u.rank
        "@gallery"       = $(if ($u.gallery) { ConvertTo-Json @($u.gallery) -Compress } else { "[]" })
        "@tasks"         = $(if ($u.tasks) { ConvertTo-Json $u.tasks -Compress } else { "{}" })
        "@redemptions"   = $(if ($u.redemptions) { ConvertTo-Json @($u.redemptions) -Compress } else { "[]" })
        "@socials"       = $(if ($u.socials) { ConvertTo-Json $u.socials -Compress } else { "{}" })
        "@aiConfig"      = $(if ($u.aiConfig) { ConvertTo-Json $u.aiConfig -Compress } else { "{}" })
        "@slug"          = [string]$u.slug
        "@photoUrl"      = [string]$u.photoUrl
        "@lastSeenMs"    = $(if ($null -ne $u.lastSeenMs) { [long]$u.lastSeenMs } else { 0 })
        "@cam2cam"       = [int]$(if ($u.cam2cam) { 1 } else { 0 })
        "@dmPolicy"      = [string]$u.dmPolicy
    }
    Invoke-SqlQuery -query $q -parameters $params | Out-Null
}

function Get-AllUsers {
    $rows = Invoke-SqlQuery -query "SELECT * FROM users"
    $list = @()
    foreach ($r in $rows) {
        $list += Map-User $r
    }
    return $list
}

function Get-Session($token) {
    if (-not $token) { return $null }
    $rows = Invoke-SqlQuery -query "SELECT * FROM sessions WHERE token = @token" -parameters @{"@token" = $token}
    if (-not $rows) { return $null }
    return @{
        token = $rows[0].token
        email = $rows[0].email
        createdAt = [long]$rows[0].createdAt
    }
}

function Save-Session($s) {
    $q = "INSERT INTO sessions (token, email, createdAt) VALUES (@token, @email, @createdAt) ON CONFLICT(token) DO UPDATE SET email=excluded.email, createdAt=excluded.createdAt"
    Invoke-SqlQuery -query $q -parameters @{"@token"=$s.token; "@email"=$s.email; "@createdAt"=[long]$s.createdAt} | Out-Null
}

function Get-Stats {
    $rows = Invoke-SqlQuery -query "SELECT * FROM stats WHERE id = 1"
    if (-not $rows) { return @{ members=0; spins=0; offersPending=0; offersAccepted=0; visits=0 } }
    return @{
        members = [int]$rows[0].members
        spins = [int]$rows[0].spins
        offersPending = [int]$rows[0].offersPending
        offersAccepted = [int]$rows[0].offersAccepted
        visits = if ($rows[0].visits -is [System.DBNull]) { 0 } else { [int]$rows[0].visits }
    }
}

function Save-Stats($s) {
    $q = "INSERT INTO stats (id, members, spins, offersPending, offersAccepted, visits) VALUES (1, @m, @s, @op, @oa, @v) ON CONFLICT(id) DO UPDATE SET members=excluded.members, spins=excluded.spins, offersPending=excluded.offersPending, offersAccepted=excluded.offersAccepted, visits=excluded.visits"
    Invoke-SqlQuery -query $q -parameters @{"@m"=[int]$s.members; "@s"=[int]$s.spins; "@op"=[int]$s.offersPending; "@oa"=[int]$s.offersAccepted; "@v"=$(if ($null -ne $s.visits) { [int]$s.visits } else { 0 })} | Out-Null
}


function Get-RoomMessages($since) {
    $rows = Invoke-SqlQuery -query "SELECT * FROM public_chat WHERE at > @since ORDER BY at ASC" -parameters @{"@since"=[long]$since}
    $list = @()
    foreach ($r in $rows) {
        $list += @{ id=$r.id; from=$r.from_email; name=$r.name; text=$r.text; at=[long]$r.at }
    }
    return $list
}

function Save-RoomMessage($m) {
    $q = "INSERT INTO public_chat (id, from_email, name, text, at) VALUES (@id, @from, @name, @text, @at)"
    Invoke-SqlQuery -query $q -parameters @{"@id"=$m.id; "@from"=$m.from; "@name"=$m.name; "@text"=$m.text; "@at"=[long]$m.at} | Out-Null
}

function Get-Feedback() {
    $rows = Invoke-SqlQuery -query "SELECT * FROM feedback ORDER BY at DESC"
    $list = @()
    foreach ($r in $rows) {
        $list += @{ id=$r.id; from=$r.from_email; text=$r.text; status=$r.status; at=[long]$r.at }
    }
    return $list
}

function Save-Feedback($f) {
    $q = "INSERT INTO feedback (id, from_email, text, status, at) VALUES (@id, @from, @text, @status, @at) ON CONFLICT(id) DO UPDATE SET status=excluded.status"
    Invoke-SqlQuery -query $q -parameters @{"@id"=$f.id; "@from"=$f.from; "@text"=$f.text; "@status"=$f.status; "@at"=[long]$f.at} | Out-Null
}

function Map-Thread($r) {
    if (-not $r) { return $null }
    return @{
        id       = $r.id
        a        = $r.email_a
        b        = $r.email_b
        lastMs   = [long]$r.lastMs
        lastRead = if ($r.lastRead -and $r.lastRead -isnot [System.DBNull]) { $r.lastRead | ConvertFrom-Json | ConvertTo-Hashtable } else { @{} }
        messages = if ($r.messages -and $r.messages -isnot [System.DBNull]) { $r.messages | ConvertFrom-Json | ConvertTo-Hashtable } else { @() }
    }
}

function Get-Thread($id) {
    $rows = Invoke-SqlQuery -query "SELECT * FROM threads WHERE id = @id" -parameters @{"@id"=$id}
    if (-not $rows) { return $null }
    return Map-Thread $rows[0]
}

function Save-Thread($t) {
    $q = "INSERT INTO threads (id, email_a, email_b, lastMs, lastRead, messages) VALUES (@id, @a, @b, @lastMs, @lastRead, @messages) ON CONFLICT(id) DO UPDATE SET lastMs=excluded.lastMs, lastRead=excluded.lastRead, messages=excluded.messages"
    $lr = if ($t.lastRead) { ConvertTo-Json $t.lastRead -Compress } else { "{}" }
    $msgs = if ($t.messages) { ConvertTo-Json @($t.messages) -Compress } else { "[]" }
    Invoke-SqlQuery -query $q -parameters @{"@id"=$t.id; "@a"=$t.a; "@b"=$t.b; "@lastMs"=[long]$t.lastMs; "@lastRead"=$lr; "@messages"=$msgs} | Out-Null
}

function Get-AllThreads() {
    $rows = Invoke-SqlQuery -query "SELECT * FROM threads"
    $list = @()
    foreach ($r in $rows) { $list += Map-Thread $r }
    return $list
}


$Script:LastSavedJson = @{
    users      = @{}
    sessions   = @{}
    stats      = ""
    threads    = @{}
    publicChat = @{}
    feedback   = @{}
    config     = @{}
}

function Get-ObjectJson($obj) {
    if ($null -eq $obj) { return "" }
    return ConvertTo-Json $obj -Compress -Depth 10
}

function Load-DatabaseToMemory {
    $db = @{ users=@{}; sessions=@{}; stats=@{members=0;spins=0;offersPending=0;offersAccepted=0}; results=@(); feedback=@(); threads=@{}; publicChat=@(); config=@{} }
    
    $Script:LastSavedJson.users.Clear()
    $Script:LastSavedJson.sessions.Clear()
    $Script:LastSavedJson.threads.Clear()
    $Script:LastSavedJson.publicChat.Clear()
    $Script:LastSavedJson.feedback.Clear()
    $Script:LastSavedJson.config.Clear()
    
    # Stats
    $db.stats = Get-Stats
    $Script:LastSavedJson.stats = Get-ObjectJson $db.stats
    
    # Users
    $rows = Invoke-SqlQuery -query "SELECT * FROM users"
    foreach ($r in $rows) {
        $u = Map-User $r
        if ($u) {
            $email = $u.email.ToLowerInvariant()
            $db.users[$email] = $u
            $Script:LastSavedJson.users[$email] = Get-ObjectJson $u
        }
    }
    
    # Sessions
    $rows = Invoke-SqlQuery -query "SELECT * FROM sessions"
    foreach ($r in $rows) {
        $db.sessions[$r.token] = $r.email
        $Script:LastSavedJson.sessions[$r.token] = $r.email
    }

    # Public Chat
    $db.publicChat = Get-RoomMessages 0
    foreach ($m in $db.publicChat) {
        $Script:LastSavedJson.publicChat[$m.id] = Get-ObjectJson $m
    }
    
    # Feedback
    $db.feedback = Get-Feedback
    foreach ($f in $db.feedback) {
        $Script:LastSavedJson.feedback[$f.id] = Get-ObjectJson $f
    }
    
    # Threads (Hashtable indexed by email_a:email_b)
    $rows = Invoke-SqlQuery -query "SELECT * FROM threads"
    foreach ($r in $rows) {
        $thread = Map-Thread $r
        if ($thread) {
            $key = $thread.id
            $db.threads[$key] = $thread
            $Script:LastSavedJson.threads[$key] = Get-ObjectJson $thread
        }
    }

    # Config
    $rows = Invoke-SqlQuery -query "SELECT * FROM config"
    foreach ($r in $rows) {
        $val = $r.value | ConvertFrom-Json | ConvertTo-Hashtable
        $db.config[$r.key] = $val
        $Script:LastSavedJson.config[$r.key] = Get-ObjectJson $val
    }

    return $db
}

function Save-MemoryToDatabase($db) {
    try {
        Invoke-SqlQuery "BEGIN TRANSACTION;"
        
        # 1. Sync Users
        if ($db.users) {
            foreach ($u in $db.users.Values) {
                $email = $u.email.ToLowerInvariant()
                $currentJson = Get-ObjectJson $u
                $lastJson = $Script:LastSavedJson.users[$email]
                if ($currentJson -ne $lastJson) {
                    Save-User $u
                    $Script:LastSavedJson.users[$email] = $currentJson
                }
            }
        }
        
        # 2. Sync Sessions
        if ($db.sessions) {
            foreach ($token in @($Script:LastSavedJson.sessions.Keys)) {
                if (-not $db.sessions.ContainsKey($token)) {
                    Invoke-SqlQuery "DELETE FROM sessions WHERE token = @token" -parameters @{"@token" = $token}
                    $Script:LastSavedJson.sessions.Remove($token) | Out-Null
                }
            }
            foreach ($token in $db.sessions.Keys) {
                $email = $db.sessions[$token]
                if ($Script:LastSavedJson.sessions[$token] -ne $email) {
                    Save-Session @{token=$token; email=$email; createdAt=0}
                    $Script:LastSavedJson.sessions[$token] = $email
                }
            }
        }
        
        # 3. Sync Stats
        if ($db.stats) {
            $currentJson = Get-ObjectJson $db.stats
            if ($currentJson -ne $Script:LastSavedJson.stats) {
                Save-Stats $db.stats
                $Script:LastSavedJson.stats = $currentJson
            }
        }
        
        # 4. Sync Threads
        if ($db.threads) {
            foreach ($key in $db.threads.Keys) {
                $t = $db.threads[$key]
                $currentJson = Get-ObjectJson $t
                $lastJson = $Script:LastSavedJson.threads[$key]
                if ($currentJson -ne $lastJson) {
                    Save-Thread $t
                    $Script:LastSavedJson.threads[$key] = $currentJson
                }
            }
        }
        
        # 5. Sync Public Chat
        if ($db.publicChat) {
            foreach ($m in $db.publicChat) {
                $currentJson = Get-ObjectJson $m
                $lastJson = $Script:LastSavedJson.publicChat[$m.id]
                if ($currentJson -ne $lastJson) {
                    Save-RoomMessage $m
                    $Script:LastSavedJson.publicChat[$m.id] = $currentJson
                }
            }
        }
        
        # 6. Sync Feedback
        if ($db.feedback) {
            foreach ($f in $db.feedback) {
                $currentJson = Get-ObjectJson $f
                $lastJson = $Script:LastSavedJson.feedback[$f.id]
                if ($currentJson -ne $lastJson) {
                    Save-Feedback $f
                    $Script:LastSavedJson.feedback[$f.id] = $currentJson
                }
            }
        }
        
        # 7. Sync Config
        if ($db.config) {
            foreach ($key in $db.config.Keys) {
                $val = $db.config[$key]
                $currentJson = Get-ObjectJson $val
                $lastJson = $Script:LastSavedJson.config[$key]
                if ($currentJson -ne $lastJson) {
                    Save-Config @{$key=$val}
                    $Script:LastSavedJson.config[$key] = $currentJson
                }
            }
        }
        
        Invoke-SqlQuery "COMMIT;"
    } catch {
        try { Invoke-SqlQuery "ROLLBACK;" } catch {}
        throw $_
    }
}

function Get-Config {
    $q = "CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT);"
    Invoke-SqlQuery $q | Out-Null
    $rows = Invoke-SqlQuery "SELECT * FROM config"
    $c = @{}
    foreach ($r in $rows) {
        $c[$r.key] = ConvertFrom-Json $r.value -AsHashtable
    }
    return $c
}

function Save-Config($c) {
    if (-not $c) { return }
    $q = "INSERT INTO config (key, value) VALUES (@k, @v) ON CONFLICT(key) DO UPDATE SET value=excluded.value"
    foreach ($k in $c.Keys) {
        $v = ConvertTo-Json $c[$k] -Compress -Depth 10
        Invoke-SqlQuery -query $q -parameters @{"@k"=$k; "@v"=$v} | Out-Null
    }
}
