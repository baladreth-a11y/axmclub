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
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
# Compiled multipart/form-data parser. PowerShell 5.1's binding/coercion
# of `byte[]` through script-level operations is unreliable for binary
# search (boundary-finding falls back to byte-by-byte comparisons that
# silently fail). The whole parser therefore lives in straight C#.
try {
  Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

public class AxmPart {
    public string Name;
    public string Filename;
    public string ContentType;
    public byte[] Bytes;
}

public static class AxmMultipart {
    static int IndexOf(byte[] hay, byte[] needle, int start) {
        if (hay == null || needle == null) return -1;
        if (needle.Length == 0) return start;
        int max = hay.Length - needle.Length;
        for (int i = start; i <= max; i++) {
            bool ok = true;
            for (int j = 0; j < needle.Length; j++) {
                if (hay[i + j] != needle[j]) { ok = false; break; }
            }
            if (ok) return i;
        }
        return -1;
    }

    static string GetDispositionParam(string headerLine, string key) {
        Match m = Regex.Match(
            headerLine,
            @"(?:^|;\s*)" + Regex.Escape(key) + @"=(?:""([^""]*)""|([^;\r\n]+))",
            RegexOptions.IgnoreCase
        );
        if (!m.Success) return "";
        string value = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value.Trim();
        if (key.Equals("filename*", StringComparison.OrdinalIgnoreCase)) {
            int marker = value.IndexOf("''", StringComparison.Ordinal);
            if (marker >= 0) value = value.Substring(marker + 2);
            try { value = Uri.UnescapeDataString(value); } catch {}
        }
        return value;
    }

    public static AxmPart[] Parse(byte[] body, string boundary) {
        if (body == null || body.Length == 0) return new AxmPart[0];
        if (string.IsNullOrEmpty(boundary)) return null;
        byte[] delim = Encoding.ASCII.GetBytes("--" + boundary);
        byte[] crlfCrlf = new byte[] { 13, 10, 13, 10 };
        List<int> positions = new List<int>();
        int idx = 0;
        while (true) {
            int next = IndexOf(body, delim, idx);
            if (next < 0) break;
            positions.Add(next);
            idx = next + delim.Length;
        }
        if (positions.Count < 2) return null;
        List<AxmPart> parts = new List<AxmPart>();
        for (int k = 0; k < positions.Count - 1; k++) {
            int start = positions[k] + delim.Length;
            // Trailing '--' marks the closing boundary; skip that part.
            if (start + 1 < body.Length && body[start] == 45 && body[start + 1] == 45) continue;
            if (start + 1 < body.Length && body[start] == 13 && body[start + 1] == 10) start += 2;
            int end = positions[k + 1];
            while (end > start && (body[end - 1] == 13 || body[end - 1] == 10)) end--;
            if (end <= start) continue;
            int hdrEnd = IndexOf(body, crlfCrlf, start);
            if (hdrEnd < 0 || hdrEnd > end) continue;
            string hdrText = Encoding.ASCII.GetString(body, start, hdrEnd - start);
            int bodyStart = hdrEnd + 4;
            int bodyLen = end - bodyStart;
            if (bodyLen < 0) bodyLen = 0;
            byte[] partBytes = new byte[bodyLen];
            if (bodyLen > 0) Buffer.BlockCopy(body, bodyStart, partBytes, 0, bodyLen);
            string name = "", filename = "", ctype = "";
            foreach (string line in hdrText.Split(new string[] { "\r\n" }, StringSplitOptions.None)) {
                if (line.StartsWith("Content-Disposition:", StringComparison.OrdinalIgnoreCase)) {
                    name = GetDispositionParam(line, "name");
                    filename = GetDispositionParam(line, "filename");
                    if (string.IsNullOrEmpty(filename)) filename = GetDispositionParam(line, "filename*");
                } else if (line.StartsWith("Content-Type:", StringComparison.OrdinalIgnoreCase)) {
                    ctype = line.Substring("Content-Type:".Length).Trim();
                }
            }
            AxmPart p = new AxmPart();
            p.Name = name; p.Filename = filename; p.ContentType = ctype; p.Bytes = partBytes;
            parts.Add(p);
        }
        return parts.ToArray();
    }

    // Read up to maxBytes from a stream into a fresh byte[] without any
    // PowerShell-side allocations / boxing.
    public static byte[] ReadAll(Stream input, long maxBytes) {
        MemoryStream ms = new MemoryStream();
        byte[] buf = new byte[8192];
        while (true) {
            int n = input.Read(buf, 0, buf.Length);
            if (n <= 0) break;
            if (ms.Length + n > maxBytes) return null;
            ms.Write(buf, 0, n);
        }
        return ms.ToArray();
    }

    // Stream-based entry point. Combines reading the body and parsing it,
    // so the raw byte[] never has to round-trip through a PowerShell
    // variable (where PS 5.1 was silently stringifying it). Returns:
    //   ParseResult.TooLarge=true    -> client exceeded maxBytes (413)
    //   ParseResult.Parts==null      -> malformed multipart (also 413)
    //   ParseResult.Parts.Length==0  -> empty body (treated as no parts)
    public static AxmParseResult ParseStream(Stream input, long maxBytes, string boundary) {
        AxmParseResult r = new AxmParseResult();
        byte[] body = ReadAll(input, maxBytes);
        if (body == null) { r.TooLarge = true; return r; }
        r.Parts = Parse(body, boundary);
        return r;
    }
}

public class AxmParseResult {
    public bool TooLarge;
    public AxmPart[] Parts;
}
"@
  Write-Host "[boot] AxmMultipart type loaded" -ForegroundColor DarkGray
} catch {
  Write-Host "[boot] AxmMultipart Add-Type FAILED: $_" -ForegroundColor Red
}

# ---------- Paths ----------
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root 'data'
$DbPath  = Join-Path $DataDir 'db.json'
$UploadsDir = Join-Path $Root 'uploads'
if (-not (Test-Path $DataDir))    { New-Item -ItemType Directory $DataDir    | Out-Null }
if (-not (Test-Path $UploadsDir)) { New-Item -ItemType Directory $UploadsDir | Out-Null }

$Script:DbLock = New-Object object
# Make $Port reachable from helpers like Send-VerifyEmail without
# requiring it to be passed around. Set after the param block runs.
$Script:Port = $Port
# Upload limits / allowed mime types are referenced by the upload handler.
$Script:UploadMaxBytes = 10485760  # 10 MB
$Script:UploadMimeTypes = @{
  'image/jpeg' = '.jpg'
  'image/png'  = '.png'
  'image/webp' = '.webp'
  'image/gif'  = '.gif'
}
$Script:GenderValues = @('male','female','crossdresser','transsexual')
$Script:GalleryMax   = 12
$Script:VerifyTtlMs  = 24 * 60 * 60 * 1000  # 24h

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
# Wheel variants. Each key is a variantId the client can spin. The
# 'default' variant is used when the client doesn't pass variantId.
# Adding a themed wheel (e.g. holiday, event) is a hashtable entry —
# no handler code changes needed.
$Script:WheelVariants = @{
  default = @(
    @{ label='10 pts';  points=10  }
    @{ label='50 pts';  points=50  }
    @{ label='100 pts'; points=100 }
    @{ label='25 pts';  points=25  }
    @{ label='500 pts'; points=500 }
    @{ label='20 pts';  points=20  }
    @{ label='75 pts';  points=75  }
    @{ label='5 pts';   points=5   }
  )
  weekend = @(
    @{ label='15 pts';   points=15   }
    @{ label='75 pts';   points=75   }
    @{ label='150 pts';  points=150  }
    @{ label='40 pts';   points=40   }
    @{ label='750 pts';  points=750  }
    @{ label='30 pts';   points=30   }
    @{ label='100 pts';  points=100  }
    @{ label='10 pts';   points=10   }
  )
}
# Back-compat alias for any inline reference that still reads Segments.
$Script:Segments = $Script:WheelVariants['default']
$Script:CooldownMs        = 24 * 60 * 60 * 1000  # 24h
$Script:StreakWindowMs    = 48 * 60 * 60 * 1000  # 48h grace to keep streak alive
$Script:StreakBonusEvery  = 7
$Script:StreakBonusPts    = 100
$Script:CamPassDurationMs = 10 * 60 * 1000       # 10 min

# Cam-room passwords (issued by the model / admin).
# `usesByUser` tracks per-user one-shot redemptions to prevent spam.
# `createdBy` records ownership: 'system' for seeded codes, 'admin' for
# operator-issued codes, or a model's email for model-issued codes. The
# model dashboard uses this field to filter to a single model's passwords.
$Script:CamPasswords = @{
  'MODEL10'    = @{ uses = 5;   note = 'Model of the day';     usesByUser = @{}; createdBy = 'system' }
  'VIP-FAST'   = @{ uses = 10;  note = 'VIP holders';           usesByUser = @{}; createdBy = 'system' }
  'OPEN-HOUSE' = @{ uses = 999; note = 'Open house — everyone'; usesByUser = @{}; createdBy = 'system' }
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

# Slugify a display name into a URL-safe lower-kebab string.
# Strips any non-alphanumeric characters, collapses runs of '-',
# trims to 48 chars. Returns 'model' if the result would be empty.
function Slugify([string]$s) {
  if (-not $s) { return 'model' }
  $lower = $s.ToLowerInvariant()
  $kebab = [regex]::Replace($lower, '[^a-z0-9]+', '-')
  $kebab = $kebab.Trim('-')
  if ($kebab.Length -eq 0) { return 'model' }
  if ($kebab.Length -gt 48) { $kebab = $kebab.Substring(0, 48).Trim('-') }
  if ($kebab.Length -eq 0) { return 'model' }
  return $kebab
}

# Generate a unique slug for a user from their display name. If a
# different user already owns the same slug, suffix '-2', '-3', etc.
function Ensure-Slug($db, $u) {
  if ($u.slug) { return [string]$u.slug }
  $base = Slugify $u.name
  $candidate = $base
  $n = 2
  while ($true) {
    $taken = $false
    foreach ($otherEmail in $db.users.Keys) {
      $other = $db.users[$otherEmail]
      if ($other -ne $u -and ($other.slug -eq $candidate)) { $taken = $true; break }
    }
    if (-not $taken) { break }
    $candidate = $base + '-' + $n
    $n++
    if ($n -gt 99) { $candidate = $base + '-' + (Get-Random -Minimum 100 -Maximum 9999); break }
  }
  $u.slug = $candidate
  return $candidate
}

# Validate / canonicalize a gender string. Returns the lower-cased
# gender if it is in the allowed set; otherwise returns $null.
function Validate-Gender($v) {
  if ($null -eq $v) { return $null }
  $g = ([string]$v).Trim().ToLowerInvariant()
  if ($g -eq '') { return '' }
  if ($Script:GenderValues -contains $g) { return $g }
  return $null
}

# Look up a user by either email or slug (case-insensitive).
function Get-ModelByEmailOrSlug($db, [string]$key) {
  if (-not $key) { return $null }
  $k = $key.ToLowerInvariant()
  if ($db.users.ContainsKey($k)) { return $db.users[$k] }
  foreach ($email in $db.users.Keys) {
    $u = $db.users[$email]
    if ($u.slug -and ([string]$u.slug).ToLowerInvariant() -eq $k) { return $u }
  }
  return $null
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
  $bio = ''
  if ($u.bio) { $bio = [string]$u.bio }
  $brand = ''
  if ($u.brandColor) { $brand = [string]$u.brandColor }
  $gender = ''
  if ($u.gender) { $gender = [string]$u.gender }
  $photo = ''
  if ($u.photoUrl) { $photo = [string]$u.photoUrl }
  $slug = ''
  if ($u.slug) { $slug = [string]$u.slug }
  $verified = $false
  if ($u.emailVerified) { $verified = [bool]$u.emailVerified }
  $galleryCount = 0
  if ($u.gallery) { $galleryCount = @($u.gallery).Count }
  $socials = @{ telegram = ''; snap = ''; webcam = ''; fansite = '' }
  if ($u.socials) {
    foreach ($k in @('telegram','snap','webcam','fansite')) {
      if ($u.socials[$k]) { $socials[$k] = [string]$u.socials[$k] }
    }
  }
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
    bio            = $bio
    brandColor     = $brand
    socials        = $socials
    gender         = $gender
    photoUrl       = $photo
    slug           = $slug
    emailVerified  = $verified
    galleryCount   = $galleryCount
  }
}

# Public model card. Strips PII / scoring info that supporters don't need.
# Used by GET /api/models (no auth) and to compose the detail payload.
function Public-Model($u) {
  if (-not $u) { return $null }
  $gender = ''
  if ($u.gender) { $gender = [string]$u.gender }
  $photo = ''
  if ($u.photoUrl) { $photo = [string]$u.photoUrl }
  $slug = ''
  if ($u.slug) { $slug = [string]$u.slug }
  $bio = ''
  if ($u.bio) { $bio = [string]$u.bio }
  $brand = ''
  if ($u.brandColor) { $brand = [string]$u.brandColor }
  $socials = @{ telegram = ''; snap = ''; webcam = ''; fansite = '' }
  if ($u.socials) {
    foreach ($k in @('telegram','snap','webcam','fansite')) {
      if ($u.socials[$k]) { $socials[$k] = [string]$u.socials[$k] }
    }
  }
  $galleryCount = 0
  if ($u.gallery) { $galleryCount = @($u.gallery).Count }
  return @{
    slug         = $slug
    name         = [string]$u.name
    gender       = $gender
    photoUrl     = $photo
    bio          = $bio
    brandColor   = $brand
    socials      = $socials
    galleryCount = $galleryCount
    joined       = [long]$u.joined
  }
}

# Public model with full gallery. Returned only to verified, signed-in users.
function Public-Model-Detail($u) {
  $base = Public-Model $u
  $gallery = @()
  if ($u.gallery) {
    foreach ($g in @($u.gallery)) {
      $url = ''
      if ($g.url) { $url = [string]$g.url }
      $at  = 0
      if ($g.addedAt) { $at = [long]$g.addedAt }
      $gallery += @{ url = $url; addedAt = $at }
    }
  }
  $base.gallery = $gallery
  return $base
}

# Resolve the on-disk uploads directory for a model and create it on demand.
# Returns the absolute path. Caller is expected to write under it; the
# path-traversal guard in Handle-Request still protects the rest of the tree.
function Get-ModelUploadDir([string]$slug) {
  if (-not $slug) { $slug = 'misc' }
  $dir = Join-Path (Join-Path $UploadsDir 'models') $slug
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  return $dir
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
    '.jpg'  { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.webp' { 'image/webp' }
    '.gif'  { 'image/gif' }
    '.ico'  { 'image/x-icon' }
    default { 'application/octet-stream' }
  }
  $bytes = [IO.File]::ReadAllBytes($fullPath)
  $resp.ContentType = $mime
  $resp.ContentLength64 = $bytes.Length
  $resp.OutputStream.Write($bytes, 0, $bytes.Length)
  $resp.OutputStream.Close()
}

# Send a plain HTML response. Used by the verification confirm endpoint
# which returns a tiny landing page rather than a JSON payload.
function Send-Html($resp, [string]$html, [int]$status = 200) {
  $resp.StatusCode = $status
  $resp.ContentType = 'text/html; charset=utf-8'
  $bytes = [Text.Encoding]::UTF8.GetBytes($html)
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

# Minimal multipart/form-data parser. Returns an array of hashtables
# @{ name=; filename=; contentType=; bytes= } — one entry per part.
# Returns $null on malformed input; caller decides how to respond.
#
# The actual byte-search and part-splitting happens in the compiled
# C# helper [AxmMultipart] (see top of file). Doing it in pure
# PowerShell on Windows PowerShell 5.1 is unreliable because byte[]
# arrays end up boxed through PSObject in non-obvious ways.
function Read-MultipartParts($req, [long]$maxBytes = 11534336) {
  $ct = [string]$req.ContentType
  if (-not $ct -or $ct -notmatch 'multipart/form-data') { return $null }
  $m = [regex]::Match($ct, 'boundary=(?:"([^"]+)"|([^;\s]+))')
  if (-not $m.Success) { return $null }
  $boundary = $m.Groups[1].Value
  if (-not $boundary) { $boundary = $m.Groups[2].Value }

  if (-not $req.HasEntityBody) { return @() }
  $declared = [long]$req.ContentLength64
  if ($declared -gt $maxBytes) { return $null }

  # Hand the stream straight to the compiled helper so the body bytes
  # never live in a PowerShell variable. Doing otherwise gives PS 5.1
  # a chance to silently stringify the byte[] on its way back through.
  Write-Host ("[mp] ParseStream declared=" + $declared + " boundary=" + $boundary) -ForegroundColor Magenta
  $result = [AxmMultipart]::ParseStream($req.InputStream, $maxBytes, $boundary)
  if ($null -eq $result) { Write-Host "[mp] ParseStream returned null result" -ForegroundColor Red; return $null }
  $partInfo = 'null'
  if ($null -ne $result.Parts) { $partInfo = [string]$result.Parts.Length }
  Write-Host ("[mp] ParseStream tooLarge=" + $result.TooLarge + " parts=" + $partInfo) -ForegroundColor Magenta
  if ($result.TooLarge) { return $null }
  if ($null -eq $result.Parts) { return $null }

  # Translate the C# AxmPart[] into a hashtable list so the rest of the
  # PowerShell code keeps its case-insensitive .name / .filename / .bytes
  # idiom.
  $parts = @()
  foreach ($p in $result.Parts) {
    $parts += @{
      name        = [string]$p.Name
      filename    = [string]$p.Filename
      contentType = [string]$p.ContentType
      bytes       = $p.Bytes
    }
  }
  return ,$parts
}

# Send a verification email or, if no SMTP is configured, fall back to
# writing the link to stdout with a [verify-link] prefix. The e2e test
# harness scrapes the captured stdout for this prefix to extract the
# token without needing a real SMTP server.
function Send-VerifyEmail([string]$toEmail, [string]$toName, [string]$token) {
  $base = $env:AURUM_BASE_URL
  if (-not $base) { $base = "http://localhost:$($Script:Port)" }
  $link = $base.TrimEnd('/') + '/api/verify/confirm?token=' + [uri]::EscapeDataString($token)

  $smtpHost = $env:AURUM_SMTP_HOST
  if (-not $smtpHost) {
    Write-Host "[verify-link] $toEmail $link" -ForegroundColor Yellow
    return
  }

  try {
    $smtpPort = 587
    if ($env:AURUM_SMTP_PORT) { $smtpPort = [int]$env:AURUM_SMTP_PORT }
    $from = $env:AURUM_SMTP_FROM
    if (-not $from) { $from = 'no-reply@axmclub.com' }

    $client = New-Object System.Net.Mail.SmtpClient($smtpHost, $smtpPort)
    $client.EnableSsl = $true
    if ($env:AURUM_SMTP_USER -and $env:AURUM_SMTP_PASS) {
      $client.Credentials = New-Object System.Net.NetworkCredential($env:AURUM_SMTP_USER, $env:AURUM_SMTP_PASS)
    }

    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From = New-Object System.Net.Mail.MailAddress($from, 'AxMclub')
    $msg.To.Add((New-Object System.Net.Mail.MailAddress($toEmail, $toName)))
    $msg.Subject = 'Verify your AxMclub email'
    $msg.Body    = "Hi $toName,`r`n`r`nConfirm your email to view model profiles on AxMclub:`r`n$link`r`n`r`nThe link expires in 24 hours."
    $msg.IsBodyHtml = $false
    $client.Send($msg)
    $msg.Dispose(); $client.Dispose()
  } catch {
    Write-Host "WARN: failed to send verify email to ${toEmail}: $_" -ForegroundColor Yellow
    Write-Host "[verify-link] $toEmail $link" -ForegroundColor Yellow
  }
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

# ==========================================================================
#  API
#  ----
#  The public API is split by domain into a small set of sub-handlers. Each
#  sub-handler returns $true when it has handled the request (regardless of
#  whether the response was a success or a structured error), and $false
#  when the route belongs to a different domain.
#
#  Handle-Api is the top-level dispatcher that walks the sub-handlers in
#  order and sends a 404 if none of them claim the route.
#
#  Adding a new endpoint:
#    1. Pick the domain it belongs to (or add a new Handle-X function).
#    2. Add a new case to that handler's switch statement.
#    3. Use `Require-Auth` to cut the 3-line 401 guard when the endpoint
#       needs a signed-in user.
# ==========================================================================

# Returns the logged-in user on success. On failure writes a 401 and
# returns $null. Inside a handler:
#   $u = Require-Auth $req $resp $db
#   if (-not $u) { return $true }   # the 401 has already been sent
function Require-Auth($req, $resp, $db) {
  $s = Get-SessionUser $req $db
  if (-not $s) {
    Send-Json $resp @{ error = 'Sign in required.' } 401
    return $null
  }
  return $s.user
}

# Returns $true if the request carries a valid x-admin-key that matches
# the AURUM_ADMIN_KEY env var. On failure writes a 403 and returns $false.
# Admin auth is intentionally env-driven so the admin panel stays disabled
# until an operator opts in by setting the key.
function Require-Admin($req, $resp) {
  $adminKey = $env:AURUM_ADMIN_KEY
  $given    = $req.Headers['x-admin-key']
  if (-not $adminKey -or $given -ne $adminKey) {
    Send-Json $resp @{ error = 'Admin only.' } 403
    return $false
  }
  return $true
}

# Returns the logged-in user when their accountType is 'model'. On failure
# writes a 401 (signed-out) or 403 (signed-in supporter) and returns $null.
# Used by every /api/model/* handler.
function Require-Model($req, $resp, $db) {
  $u = Require-Auth $req $resp $db
  if (-not $u) { return $null }
  $acct = ''
  if ($u.accountType) { $acct = [string]$u.accountType }
  if ($acct -ne 'model') {
    Send-Json $resp @{ error = 'Model accounts only.' } 403
    return $null
  }
  return $u
}

# ---- Auth: register / login / logout / me -------------------------------
function Handle-Auth($req, $resp, $db, $path, $method) {
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
        Send-Json $resp @{ error = 'Model accounts are invite-only and coming soon.' } 403
        return $true
      }
      if ($accountType -ne 'supporter') {
        Send-Json $resp @{ error = 'Invalid account type.' } 400
        return $true
      }
      if (-not $name -or -not $email -or -not $password) {
        Send-Json $resp @{ error = 'Name, email and password are required.' } 400
        return $true
      }
      if ($password.Length -lt 4) {
        Send-Json $resp @{ error = 'Password must be at least 4 characters.' } 400
        return $true
      }
      if ($db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'An account with this email already exists.' } 409
        return $true
      }
      $salt = New-Salt
      $hash = Hash-Password $password $salt
      $db.users[$email] = @{
        name          = $name
        email         = $email
        pwSalt        = $salt
        pwHash        = $hash
        points        = 0
        tokens        = 0
        rank          = ''
        offers        = @()
        lastSpin      = 0
        joined        = NowMs
        accountType   = $accountType
        emailVerified = $false
        gallery       = @()
        gender        = ''
        photoUrl      = ''
        bio           = ''
        brandColor    = ''
        socials       = @{ telegram=''; snap=''; webcam=''; fansite='' }
      }
      Ensure-Slug $db $db.users[$email] | Out-Null
      $db.stats.members = [int]$db.stats.members + 1
      $sid = New-Token
      $db.sessions[$sid] = $email
      Save-Db $db
      Send-Json $resp @{ user = (Public-User $db.users[$email]) } 200 @((Session-Cookie $sid))
      return $true
    }

    'POST /api/login' {
      $body = Read-JsonBody $req
      $email = ("$($body.email)").Trim().ToLower()
      $password = "$($body.password)"
      if (-not $db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'Invalid email or password.' } 401
        return $true
      }
      $u = $db.users[$email]
      if ((Hash-Password $password $u.pwSalt) -ne $u.pwHash) {
        Send-Json $resp @{ error = 'Invalid email or password.' } 401
        return $true
      }
      $sid = New-Token
      $db.sessions[$sid] = $email
      Save-Db $db
      Send-Json $resp @{ user = (Public-User $u) } 200 @((Session-Cookie $sid))
      return $true
    }

    'POST /api/logout' {
      $s = Get-SessionUser $req $db
      if ($s) { $db.sessions.Remove($s.sid); Save-Db $db }
      $expired = 'sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0'
      Send-Json $resp @{ ok = $true } 200 @($expired)
      return $true
    }

    'GET /api/me' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ user = $null }; return $true }
      Send-Json $resp @{ user = (Public-User $s.user) }
      return $true
    }
  }
  return $false
}

# ---- Stats --------------------------------------------------------------
function Handle-Stats($req, $resp, $db, $path, $method) {
  if ("$method $path" -eq 'GET /api/stats') {
    Send-Json $resp @{ members = [int]$db.stats.members; spins = [int]$db.stats.spins }
    return $true
  }
  return $false
}

# ---- Roulette: spin + history ------------------------------------------
function Handle-Roulette($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

    'POST /api/spin' {
      $u = Require-Auth $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $variantId = ("$($body.variantId)").Trim().ToLower()
      if (-not $variantId) { $variantId = 'default' }
      if (-not $Script:WheelVariants.ContainsKey($variantId)) {
        Send-Json $resp @{ error = 'Unknown wheel variant.' } 400
        return $true
      }
      $segments = $Script:WheelVariants[$variantId]

      $now = NowMs
      $elapsed = $now - [long]$u.lastSpin
      if ([long]$u.lastSpin -gt 0 -and $elapsed -lt $Script:CooldownMs) {
        Send-Json $resp @{ error = 'Spin on cooldown.'; remainingMs = ($Script:CooldownMs - $elapsed) } 429
        return $true
      }

      # Streak: continuing if last spin was within the streak window; otherwise reset.
      $prevStreak = 0
      if ($u.streak) { $prevStreak = [int]$u.streak }
      $newStreak = 1
      if ([long]$u.lastSpin -gt 0 -and $elapsed -lt $Script:StreakWindowMs) {
        $newStreak = $prevStreak + 1
      }

      $idx = Get-Random -Minimum 0 -Maximum $segments.Count
      $seg = $segments[$idx]
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
        variantId   = $variantId
        user        = (Public-User $u)
      }
      return $true
    }

    'GET /api/roulette/variants' {
      $list = @()
      foreach ($id in $Script:WheelVariants.Keys) {
        $segs = $Script:WheelVariants[$id]
        $list += @{
          id       = $id
          segments = @($segs | ForEach-Object { @{ label = $_.label; points = [int]$_.points } })
        }
      }
      Send-Json $resp @{ variants = @($list); default = 'default' }
      return $true
    }

    'GET /api/history' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ history = @() }; return $true }
      $h = $s.user.history
      if (-not $h) { $h = @() }
      Send-Json $resp @{ history = @($h) }
      return $true
    }
  }
  return $false
}

# ---- Rewards: list / redeem / redemptions ------------------------------
function Handle-Rewards($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

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
      return $true
    }

    'POST /api/redeem' {
      $u = Require-Auth $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $rewardId = ("$($body.rewardId)").Trim()
      if (-not $rewardId) {
        Send-Json $resp @{ error = 'rewardId is required.' } 400
        return $true
      }
      $reward = $null
      foreach ($r in $Script:Catalog) { if ($r.id -eq $rewardId) { $reward = $r; break } }
      if (-not $reward) {
        Send-Json $resp @{ error = 'Reward not found.' } 404
        return $true
      }
      $userTier = (Get-Tier $u.points).name
      if ((Get-TierRank $userTier) -lt (Get-TierRank $reward.minTier)) {
        Send-Json $resp @{ error = ('Requires ' + $reward.minTier + ' tier.') } 403
        return $true
      }
      if ([int]$u.points -lt [int]$reward.cost) {
        Send-Json $resp @{ error = 'Not enough points.' } 402
        return $true
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
      return $true
    }

    'GET /api/redemptions' {
      $s = Get-SessionUser $req $db
      if (-not $s) { Send-Json $resp @{ redemptions = @() }; return $true }
      $r = $s.user.redemptions
      if (-not $r) { $r = @() }
      Send-Json $resp @{ redemptions = @($r) }
      return $true
    }
  }
  return $false
}

# ---- Economy: tokens/buy + offer ---------------------------------------
function Handle-Economy($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

    'POST /api/tokens/buy' {
      $u = Require-Auth $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $amount = 0
      if ($body.amount) { $amount = [int]$body.amount }
      # Accept a small set of preset packs only (demo mode — no real payment).
      $allowed = @(100, 500, 1200, 3000)
      if ($allowed -notcontains $amount) {
        Send-Json $resp @{ error = 'Invalid pack size.' } 400
        return $true
      }
      if (-not $u.tokens) { $u.tokens = 0 }
      $u.tokens = [int]$u.tokens + $amount
      Save-Db $db
      Send-Json $resp @{
        ok     = $true
        bought = $amount
        user   = (Public-User $u)
      }
      return $true
    }

    'POST /api/offer' {
      $u = Require-Auth $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $target  = ("$($body.target)").Trim()
      $message = ("$($body.message)").Trim()
      if (-not $message -or $message.Length -lt 10) {
        Send-Json $resp @{ error = 'Offer must be at least 10 characters.' } 400
        return $true
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
      return $true
    }
  }
  return $false
}

# ---- Cam room: status / redeem-password / create-password --------------
function Handle-Cam($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

    'GET /api/cam/status' {
      $u = Require-Auth $req $resp $db
      if (-not $u) { return $true }
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
      return $true
    }

    'POST /api/cam/redeem-password' {
      $u = Require-Auth $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $pw = ("$($body.password)").Trim().ToUpper()
      if (-not $pw) {
        Send-Json $resp @{ error = 'Password is required.' } 400
        return $true
      }
      if (-not $Script:CamPasswords.ContainsKey($pw)) {
        Send-Json $resp @{ error = 'Invalid password.' } 404
        return $true
      }
      $entry = $Script:CamPasswords[$pw]
      if (-not $entry.usesByUser) { $entry.usesByUser = @{} }
      if ($entry.usesByUser.ContainsKey($u.email)) {
        Send-Json $resp @{ error = 'You already redeemed this password.' } 409
        return $true
      }
      if ([int]$entry.uses -le 0) {
        Send-Json $resp @{ error = 'Password has been used up.' } 410
        return $true
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
      return $true
    }

    'POST /api/cam/create-password' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $body = Read-JsonBody $req
      $pw = ("$($body.password)").Trim().ToUpper()
      $uses = 1
      if ($body.uses) { $uses = [int]$body.uses }
      $note = ("$($body.note)").Trim()
      if (-not $note) { $note = 'Admin-issued' }
      if (-not $pw) {
        Send-Json $resp @{ error = 'password is required.' } 400
        return $true
      }
      $Script:CamPasswords[$pw] = @{ uses = $uses; note = $note; usesByUser = @{}; createdBy = 'admin' }
      Send-Json $resp @{ ok = $true; password = $pw; uses = $uses; note = $note; createdBy = 'admin' }
      return $true
    }
  }
  return $false
}

# ---- Model dashboard: own profile, own passwords, targeted offers ------
# Every endpoint here requires accountType=='model'. The Require-Model
# helper writes the right 401/403 and returns $null on failure.
#
# Ownership rules:
#   * Cam passwords carry createdBy = email|'admin'|'system'. A model can
#     only see / revoke / modify passwords whose createdBy matches their
#     own email.
#   * Offers are stored on the supporter who sent them. A model sees an
#     offer when its `target` matches their display name (case-insensitive).
#   * Profile fields (bio, brandColor, socials.*) live on the user record
#     itself and are exposed by Public-User.
function Handle-Model($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

    'GET /api/model/profile' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      Send-Json $resp @{ user = (Public-User $u) }
      return $true
    }

    'POST /api/model/profile' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $changes = @{}
      # Display name (1-60 chars). Optional.
      if ($body.PSObject.Properties['name'] -or $body.ContainsKey('name')) {
        $newName = ("$($body.name)").Trim()
        if ($newName -and $newName.Length -le 60) {
          $u.name = $newName
          $changes.name = $newName
        }
      }
      # Bio (free text up to 280 chars).
      if ($body.PSObject.Properties['bio'] -or $body.ContainsKey('bio')) {
        $newBio = ("$($body.bio)").Trim()
        if ($newBio.Length -gt 280) { $newBio = $newBio.Substring(0, 280) }
        $u.bio = $newBio
        $changes.bio = $newBio
      }
      # Brand color (CSS hex like '#7c6cff'). Empty allowed (resets).
      if ($body.PSObject.Properties['brandColor'] -or $body.ContainsKey('brandColor')) {
        $newColor = ("$($body.brandColor)").Trim()
        if ($newColor -eq '' -or ($newColor -match '^#[0-9a-fA-F]{3,8}$')) {
          $u.brandColor = $newColor
          $changes.brandColor = $newColor
        }
      }
      # Socials sub-object.
      if ($body.PSObject.Properties['socials'] -or $body.ContainsKey('socials')) {
        if (-not $u.socials) { $u.socials = @{} }
        $s = $body.socials
        foreach ($k in @('telegram','snap','webcam','fansite')) {
          if ($s -and ($s.PSObject.Properties[$k] -or $s.ContainsKey($k))) {
            $val = ("$($s[$k])").Trim()
            if ($val.Length -le 200) {
              $u.socials[$k] = $val
            }
          }
        }
        $changes.socials = $u.socials
      }
      # Gender (one of male|female|crossdresser|transsexual or empty).
      if ($body.PSObject.Properties['gender'] -or $body.ContainsKey('gender')) {
        $g = Validate-Gender $body.gender
        if ($null -eq $g) {
          Send-Json $resp @{ error = 'Invalid gender. Allowed: male, female, crossdresser, transsexual.' } 400
          return $true
        }
        $u.gender = $g
        $changes.gender = $g
      }
      # photoUrl (empty, https://..., or /uploads/models/...).
      if ($body.PSObject.Properties['photoUrl'] -or $body.ContainsKey('photoUrl')) {
        $newPhoto = ("$($body.photoUrl)").Trim()
        if ($newPhoto -eq '' -or $newPhoto -match '^https://' -or $newPhoto -match '^/uploads/models/') {
          $u.photoUrl = $newPhoto
          $changes.photoUrl = $newPhoto
        } else {
          Send-Json $resp @{ error = 'photoUrl must be empty, an https URL, or /uploads/models/...' } 400
          return $true
        }
      }
      if ($changes.Keys.Count -eq 0) {
        Send-Json $resp @{ error = 'No valid fields to update.' } 400
        return $true
      }
      # Ensure the model has a slug for outbound public links.
      Ensure-Slug $db $u | Out-Null
      Save-Db $db
      Send-Json $resp @{ ok = $true; changes = $changes; user = (Public-User $u) }
      return $true
    }

    'GET /api/model/passwords' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $list = @()
      foreach ($code in $Script:CamPasswords.Keys) {
        $entry = $Script:CamPasswords[$code]
        $owner = ''
        if ($entry.createdBy) { $owner = [string]$entry.createdBy }
        if ($owner -ne $u.email) { continue }
        $redeemers = @()
        if ($entry.usesByUser) { $redeemers = @($entry.usesByUser.Keys) }
        $list += @{
          code          = $code
          uses          = [int]$entry.uses
          note          = [string]$entry.note
          createdBy     = $owner
          redeemedBy    = $redeemers
          redeemedCount = $redeemers.Count
        }
      }
      Send-Json $resp @{ passwords = @($list); count = @($list).Count }
      return $true
    }

    'POST /api/model/passwords' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $pw = ("$($body.password)").Trim().ToUpper()
      $uses = 1
      if ($body.uses) { $uses = [int]$body.uses }
      if ($uses -lt 1)   { $uses = 1 }
      if ($uses -gt 999) { $uses = 999 }
      $note = ("$($body.note)").Trim()
      if (-not $note) { $note = ('Issued by ' + $u.name) }
      if ($note.Length -gt 80) { $note = $note.Substring(0, 80) }
      if (-not $pw -or $pw.Length -lt 2 -or $pw.Length -gt 32) {
        Send-Json $resp @{ error = 'Password code must be 2-32 chars.' } 400
        return $true
      }
      if ($Script:CamPasswords.ContainsKey($pw)) {
        Send-Json $resp @{ error = 'That code already exists.' } 409
        return $true
      }
      $Script:CamPasswords[$pw] = @{
        uses       = $uses
        note       = $note
        usesByUser = @{}
        createdBy  = $u.email
      }
      Send-Json $resp @{ ok = $true; password = $pw; uses = $uses; note = $note; createdBy = $u.email }
      return $true
    }

    'POST /api/model/passwords/revoke' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $code = ("$($body.code)").Trim().ToUpper()
      if (-not $code -or -not $Script:CamPasswords.ContainsKey($code)) {
        Send-Json $resp @{ error = 'Password not found.' } 404
        return $true
      }
      $entry = $Script:CamPasswords[$code]
      $owner = ''
      if ($entry.createdBy) { $owner = [string]$entry.createdBy }
      if ($owner -ne $u.email) {
        Send-Json $resp @{ error = 'You can only revoke passwords you created.' } 403
        return $true
      }
      $entry.uses = 0
      Send-Json $resp @{ ok = $true; code = $code }
      return $true
    }

    'GET /api/model/offers' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $myName = ($u.name + '').ToLower()
      $all = @()
      foreach ($email in $db.users.Keys) {
        $sender = $db.users[$email]
        if (-not $sender.offers) { continue }
        foreach ($o in @($sender.offers)) {
          $tgt = ''
          if ($o.target) { $tgt = [string]$o.target }
          if ($tgt.ToLower() -ne $myName) { continue }
          $status = 'pending'
          if ($o.status) { $status = [string]$o.status }
          $all += @{
            id       = [string]$o.id
            from     = [string]$sender.email
            fromName = [string]$sender.name
            target   = $tgt
            message  = [string]$o.message
            status   = $status
            at       = [long]$o.at
          }
        }
      }
      $all = @($all | Sort-Object -Property { [long]$_.at } -Descending)
      Send-Json $resp @{ offers = $all; count = $all.Count }
      return $true
    }

    'POST /api/model/offers/respond' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $email   = ("$($body.userEmail)").Trim().ToLower()
      $offerId = ("$($body.offerId)").Trim()
      $status  = ("$($body.status)").Trim().ToLower()
      if (@('accepted','declined') -notcontains $status) {
        Send-Json $resp @{ error = 'Status must be accepted or declined.' } 400
        return $true
      }
      if (-not $db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'Offer not found.' } 404
        return $true
      }
      $sender = $db.users[$email]
      if (-not $sender.offers) {
        Send-Json $resp @{ error = 'Offer not found.' } 404
        return $true
      }
      $myName = ($u.name + '').ToLower()
      $found = $false
      foreach ($o in @($sender.offers)) {
        if ($o.id -ne $offerId) { continue }
        $tgt = ''
        if ($o.target) { $tgt = [string]$o.target }
        if ($tgt.ToLower() -ne $myName) {
          # Targeted at someone else - models cannot respond on their behalf.
          Send-Json $resp @{ error = 'This offer is not addressed to you.' } 403
          return $true
        }
        $o.status = $status
        $found = $true
        break
      }
      if (-not $found) {
        Send-Json $resp @{ error = 'Offer not found.' } 404
        return $true
      }
      Save-Db $db
      Send-Json $resp @{ ok = $true; offerId = $offerId; status = $status }
      return $true
    }

    'GET /api/model/stats' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $passwordsIssued = 0
      $passwordsActive = 0
      $totalRedemptions = 0
      foreach ($code in $Script:CamPasswords.Keys) {
        $entry = $Script:CamPasswords[$code]
        $owner = ''
        if ($entry.createdBy) { $owner = [string]$entry.createdBy }
        if ($owner -ne $u.email) { continue }
        $passwordsIssued += 1
        if ([int]$entry.uses -gt 0) { $passwordsActive += 1 }
        if ($entry.usesByUser) { $totalRedemptions += @($entry.usesByUser.Keys).Count }
      }
      $myName = ($u.name + '').ToLower()
      $offersTotal = 0; $offersPending = 0; $offersAccepted = 0; $offersDeclined = 0
      foreach ($email in $db.users.Keys) {
        $sender = $db.users[$email]
        if (-not $sender.offers) { continue }
        foreach ($o in @($sender.offers)) {
          $tgt = ''
          if ($o.target) { $tgt = [string]$o.target }
          if ($tgt.ToLower() -ne $myName) { continue }
          $offersTotal += 1
          $st = 'pending'
          if ($o.status) { $st = [string]$o.status }
          switch ($st) {
            'accepted' { $offersAccepted += 1 }
            'declined' { $offersDeclined += 1 }
            default    { $offersPending  += 1 }
          }
        }
      }
      Send-Json $resp @{
        passwordsIssued  = $passwordsIssued
        passwordsActive  = $passwordsActive
        totalRedemptions = $totalRedemptions
        offersTotal      = $offersTotal
        offersPending    = $offersPending
        offersAccepted   = $offersAccepted
        offersDeclined   = $offersDeclined
      }
      return $true
    }
  }
  return $false
}

# ---- Admin: inspect passwords and offers --------------------------------
function Handle-Admin($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

    'GET /api/admin/passwords' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $list = @()
      foreach ($code in $Script:CamPasswords.Keys) {
        $entry = $Script:CamPasswords[$code]
        $redeemers = @()
        if ($entry.usesByUser) { $redeemers = @($entry.usesByUser.Keys) }
        $owner = 'system'
        if ($entry.createdBy) { $owner = [string]$entry.createdBy }
        $list += @{
          code          = $code
          uses          = [int]$entry.uses
          note          = [string]$entry.note
          createdBy     = $owner
          redeemedBy    = $redeemers
          redeemedCount = $redeemers.Count
        }
      }
      Send-Json $resp @{ passwords = @($list) }
      return $true
    }

    'POST /api/admin/passwords/revoke' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $body = Read-JsonBody $req
      $code = ("$($body.code)").Trim().ToUpper()
      if (-not $code -or -not $Script:CamPasswords.ContainsKey($code)) {
        Send-Json $resp @{ error = 'Password not found.' } 404
        return $true
      }
      $Script:CamPasswords[$code].uses = 0
      Send-Json $resp @{ ok = $true; code = $code }
      return $true
    }

    'GET /api/admin/offers' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $all = @()
      foreach ($email in $db.users.Keys) {
        $u = $db.users[$email]
        if (-not $u.offers) { continue }
        foreach ($o in @($u.offers)) {
          $status = 'pending'
          if ($o.status) { $status = [string]$o.status }
          $all += @{
            id       = [string]$o.id
            from     = [string]$u.email
            fromName = [string]$u.name
            target   = [string]$o.target
            message  = [string]$o.message
            status   = $status
            at       = [long]$o.at
          }
        }
      }
      $all = @($all | Sort-Object -Property { [long]$_.at } -Descending)
      Send-Json $resp @{ offers = $all }
      return $true
    }

    'POST /api/admin/offers/status' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $body = Read-JsonBody $req
      $email   = ("$($body.userEmail)").Trim().ToLower()
      $offerId = ("$($body.offerId)").Trim()
      $status  = ("$($body.status)").Trim().ToLower()
      $valid   = @('pending','accepted','declined')
      if ($valid -notcontains $status) {
        Send-Json $resp @{ error = 'Invalid status.' } 400
        return $true
      }
      if (-not $db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'User not found.' } 404
        return $true
      }
      $u = $db.users[$email]
      if (-not $u.offers) {
        Send-Json $resp @{ error = 'Offer not found.' } 404
        return $true
      }
      $found = $false
      foreach ($o in @($u.offers)) {
        if ($o.id -eq $offerId) {
          $o.status = $status
          $found = $true
          break
        }
      }
      if (-not $found) {
        Send-Json $resp @{ error = 'Offer not found.' } 404
        return $true
      }
      Save-Db $db
      Send-Json $resp @{ ok = $true; offerId = $offerId; status = $status }
      return $true
    }

    'GET /api/admin/users' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $list = @()
      foreach ($email in $db.users.Keys) {
        $u = $db.users[$email]
        $list += @{
          email            = [string]$u.email
          name             = [string]$u.name
          accountType      = if ($u.accountType) { [string]$u.accountType } else { 'supporter' }
          tier             = (Get-Tier $u.points).name
          points           = [int]$u.points
          tokens           = if ($u.tokens) { [int]$u.tokens } else { 0 }
          rank             = if ($u.rank) { [string]$u.rank } else { '' }
          streak           = if ($u.streak) { [int]$u.streak } else { 0 }
          lastSpin         = [long]$u.lastSpin
          joined           = [long]$u.joined
          camPassExpires   = if ($u.camPassExpires) { [long]$u.camPassExpires } else { 0 }
          redemptionsCount = if ($u.redemptions) { @($u.redemptions).Count } else { 0 }
          offersCount      = if ($u.offers) { @($u.offers).Count } else { 0 }
          taskClaimsCount  = if ($u.taskClaims) { @($u.taskClaims.Keys).Count } else { 0 }
        }
      }
      $list = @($list | Sort-Object -Property { [long]$_.joined } -Descending)
      Send-Json $resp @{ users = @($list); count = @($list).Count }
      return $true
    }

    'POST /api/admin/users/adjust' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $body = Read-JsonBody $req
      $email = ("$($body.email)").Trim().ToLower()
      if (-not $db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'User not found.' } 404
        return $true
      }
      $u = $db.users[$email]
      $changes = @{}
      # Name (string, 1-60 chars)
      if ($body.PSObject.Properties['name'] -or $body.ContainsKey('name')) {
        $newName = ("$($body.name)").Trim()
        if ($newName -and $newName.Length -le 60) {
          $u.name = $newName
          $changes.name = $newName
        }
      }
      # Points (non-negative int)
      if ($body.PSObject.Properties['points'] -or $body.ContainsKey('points')) {
        $newPoints = [int]$body.points
        if ($newPoints -lt 0) { $newPoints = 0 }
        $u.points = $newPoints
        $changes.points = $newPoints
      }
      # Tokens (non-negative int)
      if ($body.PSObject.Properties['tokens'] -or $body.ContainsKey('tokens')) {
        $newTokens = [int]$body.tokens
        if ($newTokens -lt 0) { $newTokens = 0 }
        $u.tokens = $newTokens
        $changes.tokens = $newTokens
      }
      # AccountType (supporter|model)
      if ($body.PSObject.Properties['accountType'] -or $body.ContainsKey('accountType')) {
        $newType = ("$($body.accountType)").Trim().ToLower()
        if ($newType -in @('supporter','model')) {
          $u.accountType = $newType
          $changes.accountType = $newType
        }
      }
      # Rank (free-form string, max 32 chars)
      if ($body.PSObject.Properties['rank'] -or $body.ContainsKey('rank')) {
        $newRank = ("$($body.rank)").Trim()
        if ($newRank.Length -le 32) {
          $u.rank = $newRank
          $changes.rank = $newRank
        }
      }
      if ($changes.Keys.Count -eq 0) {
        Send-Json $resp @{ error = 'No valid fields to adjust.' } 400
        return $true
      }
      Save-Db $db
      Send-Json $resp @{ ok = $true; email = $email; changes = $changes; user = (Public-User $u) }
      return $true
    }

    'POST /api/admin/users/delete' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $body = Read-JsonBody $req
      $email = ("$($body.email)").Trim().ToLower()
      if (-not $db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'User not found.' } 404
        return $true
      }
      # Drop any active sessions belonging to this user, decrement member count.
      $deadSids = @()
      foreach ($sid in @($db.sessions.Keys)) {
        if ($db.sessions[$sid] -eq $email) { $deadSids += $sid }
      }
      foreach ($sid in $deadSids) { $db.sessions.Remove($sid) | Out-Null }
      $db.users.Remove($email) | Out-Null
      $db.stats.members = [math]::Max(0, [int]$db.stats.members - 1)
      Save-Db $db
      Send-Json $resp @{ ok = $true; email = $email; sessionsDropped = $deadSids.Count }
      return $true
    }

    'POST /api/admin/users/verify' {
      if (-not (Require-Admin $req $resp)) { return $true }
      $body = Read-JsonBody $req
      $email = ("$($body.email)").Trim().ToLower()
      if (-not $db.users.ContainsKey($email)) {
        Send-Json $resp @{ error = 'User not found.' } 404
        return $true
      }
      $u = $db.users[$email]
      $u.emailVerified = $true
      $u.verifyToken = ''
      $u.verifyTokenExpires = 0
      Save-Db $db
      Send-Json $resp @{ ok = $true; email = $email; user = (Public-User $u) }
      return $true
    }
  }
  return $false
}

# ---- Public model gallery: list + slug detail (verification gated) -----
# These endpoints power the dynamic Players grid on / and /players.html.
# Anonymous visitors can browse the cards (Public-Model strips PII), but
# the per-model detail view (gallery + full bio) requires the caller to be
# signed in AND have emailVerified == $true.
function Handle-Models($req, $resp, $db, $path, $method) {
  if ("$method $path" -eq 'GET /api/models') {
    $list = @()
    foreach ($email in $db.users.Keys) {
      $u = $db.users[$email]
      $acct = ''
      if ($u.accountType) { $acct = [string]$u.accountType }
      if ($acct -ne 'model') { continue }
      Ensure-Slug $db $u | Out-Null
      $list += (Public-Model $u)
    }
    $list = @($list | Sort-Object -Property { [long]$_.joined } -Descending)
    Send-Json $resp @{ models = @($list); count = @($list).Count }
    return $true
  }

  if ($method -eq 'GET' -and $path -like '/api/models/*') {
    $slug = $path.Substring('/api/models/'.Length)
    if ($slug.Contains('/')) { $slug = $slug.Split('/')[0] }
    if (-not $slug) {
      Send-Json $resp @{ error = 'Model slug required.' } 404
      return $true
    }
    $target = Get-ModelByEmailOrSlug $db $slug
    if (-not $target -or ([string]$target.accountType) -ne 'model') {
      Send-Json $resp @{ error = 'Model not found.' } 404
      return $true
    }
    $s = Get-SessionUser $req $db
    if (-not $s) {
      Send-Json $resp @{ error = 'Sign in required.'; reason = 'sign-in' } 401
      return $true
    }
    $viewer = $s.user
    $verified = $false
    if ($viewer.emailVerified) { $verified = [bool]$viewer.emailVerified }
    # The model can view their own profile without verifying; everyone else
    # has to confirm their email first.
    if (-not $verified -and ([string]$viewer.email) -ne ([string]$target.email)) {
      Send-Json $resp @{ error = 'Verify your email to view model profiles.'; reason = 'verify-email' } 403
      return $true
    }
    Send-Json $resp @{ model = (Public-Model-Detail $target) }
    return $true
  }

  return $false
}

# ---- Email verification: start / confirm -------------------------------
function Handle-Verify($req, $resp, $db, $path, $method) {
  if ("$method $path" -eq 'POST /api/verify/start') {
    $u = Require-Auth $req $resp $db
    if (-not $u) { return $true }
    if ($u.emailVerified) {
      Send-Json $resp @{ ok = $true; alreadyVerified = $true }
      return $true
    }
    $token = New-Token
    $u.verifyToken = $token
    $u.verifyTokenExpires = (NowMs) + $Script:VerifyTtlMs
    Save-Db $db
    Send-VerifyEmail $u.email $u.name $token
    Send-Json $resp @{ ok = $true; sent = $true }
    return $true
  }

  if ("$method $path" -eq 'GET /api/verify/confirm') {
    $token = ''
    if ($req.Url.Query) {
      $q = [System.Web.HttpUtility]::ParseQueryString($req.Url.Query)
      $token = [string]$q['token']
    }
    $foundUser = $null
    if ($token) {
      foreach ($email in $db.users.Keys) {
        $u = $db.users[$email]
        if ($u.verifyToken -and ([string]$u.verifyToken) -eq $token) { $foundUser = $u; break }
      }
    }
    if (-not $foundUser) {
      $html = '<!doctype html><meta charset="utf-8"><title>Link invalid</title>' +
              '<body style="font-family:Inter,system-ui,sans-serif;background:#0a0c11;color:#eef1f6;padding:48px;text-align:center">' +
              '<h1 style="font-family:Playfair Display,serif;color:#d4af6a">Link invalid or expired</h1>' +
              '<p>Please request a new verification email from your account.</p>' +
              '<p><a href="/" style="color:#d4af6a">Back to AxMclub</a></p></body>'
      Send-Html $resp $html 400
      return $true
    }
    $now = NowMs
    $exp = 0
    if ($foundUser.verifyTokenExpires) { $exp = [long]$foundUser.verifyTokenExpires }
    if ($exp -gt 0 -and $exp -lt $now) {
      $foundUser.verifyToken = ''
      $foundUser.verifyTokenExpires = 0
      Save-Db $db
      $html = '<!doctype html><meta charset="utf-8"><title>Link expired</title>' +
              '<body style="font-family:Inter,system-ui,sans-serif;background:#0a0c11;color:#eef1f6;padding:48px;text-align:center">' +
              '<h1 style="font-family:Playfair Display,serif;color:#d4af6a">Link expired</h1>' +
              '<p>Please sign in and request a new verification email.</p>' +
              '<p><a href="/" style="color:#d4af6a">Back to AxMclub</a></p></body>'
      Send-Html $resp $html 400
      return $true
    }
    $foundUser.emailVerified = $true
    $foundUser.verifyToken = ''
    $foundUser.verifyTokenExpires = 0
    Save-Db $db
    $html = '<!doctype html><meta charset="utf-8"><title>Email verified</title>' +
            '<body style="font-family:Inter,system-ui,sans-serif;background:#0a0c11;color:#eef1f6;padding:48px;text-align:center">' +
            '<h1 style="font-family:Playfair Display,serif;color:#d4af6a">Email verified</h1>' +
            '<p>You can now view model profiles on AxMclub.</p>' +
            '<p><a href="/?verified=1" style="color:#d4af6a;font-weight:600">Continue to AxMclub</a></p></body>'
    Send-Html $resp $html 200
    return $true
  }
  return $false
}

# ---- Photo uploads (model-only, multipart): main photo + gallery -------
function Handle-Uploads($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

    'POST /api/model/photo' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $parts = Read-MultipartParts $req ($Script:UploadMaxBytes + 1048576)

      if ($null -eq $parts) {
        Send-Json $resp @{ error = 'Upload too large or malformed (10 MB max).' } 413

        return $true
      }
      $photoPart = $null
      foreach ($p in $parts) {
        if ($p.name -eq 'photo' -and $p.filename) { $photoPart = $p; break }
      }
      if (-not $photoPart) {
        Send-Json $resp @{ error = 'photo field is required.' } 400
        return $true
      }
      if (-not $Script:UploadMimeTypes.ContainsKey($photoPart.contentType)) {
        Send-Json $resp @{ error = ('Unsupported type: ' + $photoPart.contentType) } 415
        return $true
      }
      if (@($photoPart.bytes).Count -gt $Script:UploadMaxBytes) {
        Send-Json $resp @{ error = 'Photo exceeds 10 MB.' } 413

        return $true
      }
      $ext = $Script:UploadMimeTypes[$photoPart.contentType]
      $slug = Ensure-Slug $db $u
      $dir = Get-ModelUploadDir $slug
      # Remove any prior main.* file so the URL keeps a stable name with new ext.
      foreach ($prior in Get-ChildItem -Path $dir -Filter 'main.*' -ErrorAction SilentlyContinue) {
        try { Remove-Item -Force $prior.FullName -ErrorAction SilentlyContinue } catch {}
      }
      $filePath = Join-Path $dir ('main' + $ext)
      [IO.File]::WriteAllBytes($filePath, $photoPart.bytes)
      $u.photoUrl = '/uploads/models/' + $slug + '/main' + $ext
      Save-Db $db
      Send-Json $resp @{ ok = $true; photoUrl = $u.photoUrl; user = (Public-User $u) }
      return $true
    }

    'POST /api/model/gallery/add' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      if (-not $u.gallery) { $u.gallery = @() }
      if (@($u.gallery).Count -ge $Script:GalleryMax) {
        Send-Json $resp @{ error = ('Gallery is full (max ' + $Script:GalleryMax + ').') } 409
        return $true
      }
      $parts = Read-MultipartParts $req ($Script:UploadMaxBytes + 1048576)
      if ($null -eq $parts) {
        Send-Json $resp @{ error = 'Upload too large or malformed (10 MB max).' } 413
        return $true
      }
      $photoPart = $null
      foreach ($p in $parts) {
        if ($p.name -eq 'photo' -and $p.filename) { $photoPart = $p; break }
      }
      if (-not $photoPart) {
        Send-Json $resp @{ error = 'photo field is required.' } 400
        return $true
      }
      if (-not $Script:UploadMimeTypes.ContainsKey($photoPart.contentType)) {
        Send-Json $resp @{ error = ('Unsupported type: ' + $photoPart.contentType) } 415
        return $true
      }
      if (@($photoPart.bytes).Count -gt $Script:UploadMaxBytes) {
        Send-Json $resp @{ error = 'Photo exceeds 10 MB.' } 413
        return $true
      }
      $ext = $Script:UploadMimeTypes[$photoPart.contentType]
      $slug = Ensure-Slug $db $u
      $dir = Get-ModelUploadDir $slug
      $now = NowMs
      $idx = (@($u.gallery).Count + 1)
      $name = 'g' + $idx + '-' + $now + $ext
      $filePath = Join-Path $dir $name
      [IO.File]::WriteAllBytes($filePath, $photoPart.bytes)
      $url = '/uploads/models/' + $slug + '/' + $name
      $u.gallery = @($u.gallery) + @{ url = $url; addedAt = $now }
      Save-Db $db
      Send-Json $resp @{ ok = $true; gallery = @($u.gallery); user = (Public-User $u) }
      return $true
    }

    'POST /api/model/gallery/remove' {
      $u = Require-Model $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $url = ("$($body.url)").Trim()
      if (-not $url) {
        Send-Json $resp @{ error = 'url is required.' } 400
        return $true
      }
      $slug = Ensure-Slug $db $u
      $expectedPrefix = '/uploads/models/' + $slug + '/'
      if (-not $url.StartsWith($expectedPrefix)) {
        Send-Json $resp @{ error = 'You can only remove your own photos.' } 403
        return $true
      }
      if (-not $u.gallery) { $u.gallery = @() }
      $kept = @()
      $found = $false
      foreach ($g in @($u.gallery)) {
        if (([string]$g.url) -eq $url) { $found = $true; continue }
        $kept += $g
      }
      if (-not $found) {
        Send-Json $resp @{ error = 'Photo not found.' } 404
        return $true
      }
      $u.gallery = $kept
      # Also delete the on-disk file. Use Get-ModelUploadDir to be safe
      # against path-traversal.
      $rel = $url.Substring('/uploads/models/'.Length)  # 'slug/file.ext'
      $filename = $rel.Split('/')[-1]
      $dir = Get-ModelUploadDir $slug
      $filePath = Join-Path $dir $filename
      try { Remove-Item -Force $filePath -ErrorAction SilentlyContinue } catch {}
      Save-Db $db
      Send-Json $resp @{ ok = $true; gallery = @($u.gallery); user = (Public-User $u) }
      return $true
    }
  }
  return $false
}

# ---- Tasks: list / claim -----------------------------------------------
function Handle-Tasks($req, $resp, $db, $path, $method) {
  $key = "$method $path"
  switch ($key) {

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
      return $true
    }

    'POST /api/tasks/claim' {
      $u = Require-Auth $req $resp $db
      if (-not $u) { return $true }
      $body = Read-JsonBody $req
      $id = ("$($body.taskId)").Trim()
      if (-not $id) {
        Send-Json $resp @{ error = 'taskId is required.' } 400
        return $true
      }
      $task = $null
      foreach ($t in $Script:Tasks) { if ($t.id -eq $id) { $task = $t; break } }
      if (-not $task) {
        Send-Json $resp @{ error = 'Task not found.' } 404
        return $true
      }
      if (-not $u.taskClaims) { $u.taskClaims = @{} }
      $now = NowMs
      if ($u.taskClaims.ContainsKey($task.id)) {
        $prev = [long]$u.taskClaims[$task.id]
        if ([long]$task.cooldownMs -eq 0) {
          Send-Json $resp @{ error = 'One-time task already claimed.' } 409
          return $true
        }
        $elapsed = $now - $prev
        if ($elapsed -lt [long]$task.cooldownMs) {
          Send-Json $resp @{ error = 'Task on cooldown.'; remainingMs = ([long]$task.cooldownMs - $elapsed) } 429
          return $true
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
      return $true
    }
  }
  return $false
}

# ---- Community: leaderboard --------------------------------------------
function Handle-Community($req, $resp, $db, $path, $method) {
  if ("$method $path" -eq 'GET /api/leaderboard') {
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
    return $true
  }
  return $false
}

# ---- Top-level dispatcher ----------------------------------------------
function Handle-Api($req, $resp, $path, $method) {
  $db = Load-Db
  if (Handle-Auth      $req $resp $db $path $method) { return }
  if (Handle-Stats     $req $resp $db $path $method) { return }
  if (Handle-Roulette  $req $resp $db $path $method) { return }
  if (Handle-Rewards   $req $resp $db $path $method) { return }
  if (Handle-Economy   $req $resp $db $path $method) { return }
  if (Handle-Cam       $req $resp $db $path $method) { return }
  if (Handle-Tasks     $req $resp $db $path $method) { return }
  if (Handle-Community $req $resp $db $path $method) { return }
  # Public model gallery + per-model detail (verification gated).
  if (Handle-Models    $req $resp $db $path $method) { return }
  # Email verification: start + confirm.
  if (Handle-Verify    $req $resp $db $path $method) { return }
  # Photo uploads: model main photo + gallery add/remove.
  if (Handle-Uploads   $req $resp $db $path $method) { return }
  if (Handle-Model     $req $resp $db $path $method) { return }
  if (Handle-Admin     $req $resp $db $path $method) { return }
  Send-Json $resp @{ error = 'Not found.' } 404
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
# HttpListener prefix matching is exact on the Host header. We register
# both 'localhost' and '127.0.0.1' so reverse proxies (Caddy) and probes
# that use the loopback IP literal route to the same listener. Both are
# loopback-only so no URL ACL admin grant is required.
$listener = New-Object System.Net.HttpListener
$prefixes = @("http://localhost:$Port/", "http://127.0.0.1:$Port/")
foreach ($p in $prefixes) { $listener.Prefixes.Add($p) }
try { $listener.Start() }
catch {
  Write-Host ("Could not bind to: " + ($prefixes -join ', ')) -ForegroundColor Red
  Write-Host "Try a different port:  powershell -File .\server.ps1 -Port 8080" -ForegroundColor Yellow
  throw
}

Write-Host ""
Write-Host "  AxMclub.com backend running" -ForegroundColor Green
foreach ($p in $prefixes) { Write-Host ("  -> " + $p) -ForegroundColor Cyan }
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
