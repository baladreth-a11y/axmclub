$Script:SqliteConn = $null
$Script:SqlitePath = Join-Path $DataDir 'database.sqlite'

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
    $rows = Invoke-SqlQuery -query "SELECT * FROM users WHERE email = @email" -parameters @{"@email" = $email.ToLowerInvariant()}
    if (-not $rows) { return $null }
    $r = $rows[0]
    
    $u = @{
        email = $r.email
        name = if ($r.name -is [System.DBNull]) { $null } else { $r.name }
        password = $r.password
        points = [int]$r.points
        tokens = [int]$r.tokens
        spins = [int]$r.spins
        lastSpin = [long]$r.lastSpin
        isModel = [bool]$r.isModel
        createdAt = [long]$r.createdAt
        rank = if ($r.rank -is [System.DBNull]) { $null } else { $r.rank }
        cam2cam = [bool]$r.cam2cam
        bio = if ($r.bio -is [System.DBNull]) { $null } else { $r.bio }
        photo = if ($r.photo -is [System.DBNull]) { $null } else { $r.photo }
        gallery = if ($r.gallery -and $r.gallery -ne "[]") { ConvertFrom-Json $r.gallery } else { @() }
        tasks = if ($r.tasks -and $r.tasks -ne "{}") { ConvertFrom-Json $r.tasks -AsHashtable } else { @{} }
        redemptions = if ($r.redemptions -and $r.redemptions -ne "[]") { ConvertFrom-Json $r.redemptions } else { @() }
    }
    return $u
}

function Save-User($u) {
    $q = @"
    INSERT INTO users (email, name, password, points, tokens, spins, lastSpin, isModel, createdAt, rank, cam2cam, bio, photo, gallery, tasks, redemptions)
    VALUES (@email, @name, @password, @points, @tokens, @spins, @lastSpin, @isModel, @createdAt, @rank, @cam2cam, @bio, @photo, @gallery, @tasks, @redemptions)
    ON CONFLICT(email) DO UPDATE SET
        name=excluded.name, password=excluded.password, points=excluded.points, tokens=excluded.tokens,
        spins=excluded.spins, lastSpin=excluded.lastSpin, isModel=excluded.isModel, createdAt=excluded.createdAt,
        rank=excluded.rank, cam2cam=excluded.cam2cam, bio=excluded.bio, photo=excluded.photo,
        gallery=excluded.gallery, tasks=excluded.tasks, redemptions=excluded.redemptions;
"@
    $p = @{
        "@email" = $u.email.ToLowerInvariant()
        "@name" = if ($u.name) { $u.name } else { [System.DBNull]::Value }
        "@password" = $u.password
        "@points" = [int]$u.points
        "@tokens" = [int]$u.tokens
        "@spins" = [int]$u.spins
        "@lastSpin" = [long]$u.lastSpin
        "@isModel" = if ($u.isModel) { 1 } else { 0 }
        "@createdAt" = [long]$u.createdAt
        "@rank" = if ($u.rank) { $u.rank } else { [System.DBNull]::Value }
        "@cam2cam" = if ($u.cam2cam) { 1 } else { 0 }
        "@bio" = if ($u.bio) { $u.bio } else { [System.DBNull]::Value }
        "@photo" = if ($u.photo) { $u.photo } else { [System.DBNull]::Value }
        "@gallery" = if ($u.gallery) { ConvertTo-Json @($u.gallery) -Compress } else { "[]" }
        "@tasks" = if ($u.tasks) { ConvertTo-Json $u.tasks -Compress } else { "{}" }
        "@redemptions" = if ($u.redemptions) { ConvertTo-Json @($u.redemptions) -Compress } else { "[]" }
    }
    Invoke-SqlQuery -query $q -parameters $p | Out-Null
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


function Load-DatabaseToMemory {
    $db = @{
        users    = @{}
        sessions = @{}
        stats    = Get-Stats
        results  = @()
        feedback = @()
        threads  = @{}
        publicChat = Get-RoomMessages 0
        config   = Get-Config
    }
    
    foreach ($u in Get-AllUsers) { $db.users[$u.email] = $u }
    
    $rows = Invoke-SqlQuery "SELECT * FROM sessions"
    foreach ($r in $rows) {
        $db.sessions[$r.token] = @{ token=$r.token; email=$r.email; createdAt=[long]$r.createdAt }
    }
    
    foreach ($f in Get-Feedback) { $db.feedback += $f }
    
    foreach ($t in Get-AllThreads) { $db.threads[$t.id] = $t }
    
    return $db
}

function Save-MemoryToDatabase($db) {
    if ($db.users) { foreach ($u in $db.users.Values) { Save-User $u } }
    if ($db.sessions) { foreach ($s in $db.sessions.Values) { Save-Session $s } }
    if ($db.stats) { Save-Stats $db.stats }
    if ($db.threads) { foreach ($t in $db.threads.Values) { Save-Thread $t } }
    if ($db.publicChat) { foreach ($m in $db.publicChat) { Save-RoomMessage $m } }
    if ($db.feedback) { foreach ($f in $db.feedback) { Save-Feedback $f } }
    if ($db.config) { Save-Config $db.config }
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
