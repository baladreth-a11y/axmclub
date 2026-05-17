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
    aiConfig TEXT
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
    offersAccepted INTEGER
);
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
);
INSERT OR IGNORE INTO stats (id, members, spins, offersPending, offersAccepted) VALUES (1, 0, 0, 0, 0);
INSERT OR IGNORE INTO users (email, name, pwHash, pwSalt, points, tokens, spins, lastSpinMs, accountType, joinedMs, emailVerified, verifyToken, verifyTokenExpires, bio, brandColor, gender, rank, gallery, tasks, redemptions, socials) 
VALUES ('luna@example.com', 'Luna', '', '', 0, 0, 0, 0, 'ai', 1700000000000, 1, '', 0, 'Your sweet and helpful AI companion. I am always online and ready to chat. Let''s get to know each other!', '#00f2fe', 'female', 'Platinum', '[]', '{}', '[]', '{}');
"@
    $cmd = $Script:SqliteConn.CreateCommand()
    $cmd.CommandText = $schema
    $cmd.ExecuteNonQuery() | Out-Null

    # Dynamic Column Migration check: Ensure existing SQLite files get the new aiConfig column
    $colsCmd = $Script:SqliteConn.CreateCommand()
    $colsCmd.CommandText = "PRAGMA table_info(users)"
    $reader = $colsCmd.ExecuteReader()
    $hasAiConfig = $false
    while ($reader.Read()) {
        if ($reader.GetValue(1) -eq 'aiConfig') { $hasAiConfig = $true }
    }
    $reader.Close()
    if (-not $hasAiConfig) {
        $alterCmd = $Script:SqliteConn.CreateCommand()
        $alterCmd.CommandText = "ALTER TABLE users ADD COLUMN aiConfig TEXT"
        $alterCmd.ExecuteNonQuery() | Out-Null
    }
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

function Get-User($email) {
    if (-not $email) { return $null }
    $emailLc = $email.ToLowerInvariant()
    $rows = Invoke-SqlQuery -query "SELECT * FROM users WHERE email = @email" -parameters @{"@email" = $emailLc}
    if (-not $rows) { return $null }
    $r = $rows[0]
    
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
    }
    return $u
}

function Save-User($u) {
    $q = "INSERT OR REPLACE INTO users (email, name, pwHash, pwSalt, points, tokens, spins, lastSpinMs, accountType, joinedMs, emailVerified, verifyToken, verifyTokenExpires, bio, brandColor, gender, rank, gallery, tasks, redemptions, socials, aiConfig) 
          VALUES (@email, @name, @pwHash, @pwSalt, @points, @tokens, @spins, @lastSpinMs, @accountType, @joinedMs, @emailVerified, @verifyToken, @verifyTokenExpires, @bio, @brandColor, @gender, @rank, @gallery, @tasks, @redemptions, @socials, @aiConfig)"
    
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
    }
    Invoke-SqlQuery -query $q -parameters $params | Out-Null
}

function Get-AllUsers {
    $rows = Invoke-SqlQuery -query "SELECT email FROM users"
    $list = @()
    foreach ($r in $rows) {
        $list += Get-User $r.email
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
    if (-not $rows) { return @{ members=0; spins=0; offersPending=0; offersAccepted=0 } }
    return @{
        members = [int]$rows[0].members
        spins = [int]$rows[0].spins
        offersPending = [int]$rows[0].offersPending
        offersAccepted = [int]$rows[0].offersAccepted
    }
}

function Save-Stats($s) {
    $q = "INSERT INTO stats (id, members, spins, offersPending, offersAccepted) VALUES (1, @m, @s, @op, @oa) ON CONFLICT(id) DO UPDATE SET members=excluded.members, spins=excluded.spins, offersPending=excluded.offersPending, offersAccepted=excluded.offersAccepted"
    Invoke-SqlQuery -query $q -parameters @{"@m"=[int]$s.members; "@s"=[int]$s.spins; "@op"=[int]$s.offersPending; "@oa"=[int]$s.offersAccepted} | Out-Null
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

function Get-Thread($id) {
    $rows = Invoke-SqlQuery -query "SELECT * FROM threads WHERE id = @id" -parameters @{"@id"=$id}
    if (-not $rows) { return $null }
    $r = $rows[0]
    return @{
        id = $r.id
        a = $r.email_a
        b = $r.email_b
        lastMs = [long]$r.lastMs
        lastRead = if ($r.lastRead) { ConvertFrom-Json $r.lastRead -AsHashtable } else { @{} }
        messages = if ($r.messages) { ConvertFrom-Json $r.messages } else { @() }
    }
}

function Save-Thread($t) {
    $q = "INSERT INTO threads (id, email_a, email_b, lastMs, lastRead, messages) VALUES (@id, @a, @b, @lastMs, @lastRead, @messages) ON CONFLICT(id) DO UPDATE SET lastMs=excluded.lastMs, lastRead=excluded.lastRead, messages=excluded.messages"
    $lr = if ($t.lastRead) { ConvertTo-Json $t.lastRead -Compress } else { "{}" }
    $msgs = if ($t.messages) { ConvertTo-Json @($t.messages) -Compress } else { "[]" }
    Invoke-SqlQuery -query $q -parameters @{"@id"=$t.id; "@a"=$t.a; "@b"=$t.b; "@lastMs"=[long]$t.lastMs; "@lastRead"=$lr; "@messages"=$msgs} | Out-Null
}

function Get-AllThreads() {
    $rows = Invoke-SqlQuery -query "SELECT id FROM threads"
    $list = @()
    foreach ($r in $rows) { $list += Get-Thread $r.id }
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
    $row = Invoke-SqlQuery -query "SELECT * FROM stats WHERE id = 1"
    if ($row) {
        $db.stats.members = [int]$row.members
        $db.stats.spins = [int]$row.spins
        $db.stats.offersPending = [int]$row.offersPending
        $db.stats.offersAccepted = [int]$row.offersAccepted
    }
    $Script:LastSavedJson.stats = Get-ObjectJson $db.stats
    
    # Users
    $rows = Invoke-SqlQuery -query "SELECT email FROM users"
    foreach ($r in $rows) {
        $u = Get-User $r.email
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
        $key = "$($r.email_a):$($r.email_b)"
        $thread = @{
            id       = $r.id
            a        = $r.email_a
            b        = $r.email_b
            lastMs   = [long]$r.lastMs
            lastRead = if ($r.lastRead -is [System.DBNull]) { @{} } else { $r.lastRead | ConvertFrom-Json | ConvertTo-Hashtable }
            messages = if ($r.messages -is [System.DBNull]) { @() } else { $r.messages | ConvertFrom-Json | ConvertTo-Hashtable }
        }
        $db.threads[$key] = $thread
        $Script:LastSavedJson.threads[$key] = Get-ObjectJson $thread
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
