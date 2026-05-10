$email = "test@example.com"
$body = @{
    name = "Test User"
    email = $email
    password = "password123"
}
$bodyJson = $body | ConvertTo-Json

# Mocking the server environment
$Script:DataDir = ".\data"
$Script:DbPath = ".\data\db.json"
if (-not (Test-Path $Script:DataDir)) { New-Item -ItemType Directory -Path $Script:DataDir }

function NowMs { [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }
function New-Token { 
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes) -replace '\+','-' -replace '/','_' -replace '=',''
}
function Save-Db($db) {
    try {
        $json = $db | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($Script:DbPath, $json)
        return $true
    } catch {
        Write-Host "Save-Db failed: $_"
        return $false
    }
}
function Get-Db {
    if (-not (Test-Path $Script:DbPath)) {
        return @{ users = @{}; sessions = @{}; stats = @{ spins = 0; members = 0 } }
    }
    return Get-Content $Script:DbPath | ConvertFrom-Json
}

# Simulate registration
$db = Get-Db
if ($db.users.ContainsKey($email)) {
    Write-Host "User already exists"
} else {
    $db.users[$email] = @{
        name = $body.name
        email = $email
        password = $body.password # In real server this is hashed
        joined = (NowMs)
    }
    $db.stats.members++
    if (Save-Db $db) {
        Write-Host "Registration successful"
    } else {
        Write-Host "Registration failed"
    }
}
