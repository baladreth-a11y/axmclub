$env:AURUM_ADMIN_KEY='test-admin-key'
$port = 8080

# Start server process and redirect output to a file
Write-Host "Starting server on port $port..."
$p = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File server.ps1 -Port $port" -PassThru -NoNewWindow -RedirectStandardOutput "scratch\server-stdout.log" -RedirectStandardError "scratch\server-stderr.log"

Start-Sleep -Seconds 3

# 1. Edit Luna
$adjustBody = @{
  email = "luna@example.com"
  name = "Luna"
  points = 200
  tokens = 20
  accountType = "model"
  rank = ""
  emailVerified = $true
} | ConvertTo-Json

Write-Host "Sending POST /api/admin/users/adjust..."
try {
  $res1 = Invoke-RestMethod -Uri "http://localhost:$port/api/admin/users/adjust" -Method Post -Headers @{"x-admin-key"="test-admin-key"} -Body $adjustBody -ContentType "application/json"
  Write-Host "Luna edit response: $res1"
} catch {
  Write-Host "Luna edit failed: $_"
}

Start-Sleep -Seconds 1

# 2. Register new supporter with a random email
$rand = Get-Random -Minimum 1000 -Maximum 9999
$email = "subagent_test_${rand}@example.com"
$registerBody = @{
  name = "Subagent Test"
  email = $email
  password = "password123"
  accountType = "supporter"
} | ConvertTo-Json

Write-Host "Sending POST /api/register for $email..."
try {
  $res2 = Invoke-RestMethod -Uri "http://localhost:$port/api/register" -Method Post -Body $registerBody -ContentType "application/json"
  Write-Host "Register response: $res2"
} catch {
  Write-Host "Register failed: $_"
}

Start-Sleep -Seconds 2

# Check if server process is still running
if ($p.HasExited) {
  Write-Host "CRASH DETECTED! Server process exited with code $($p.ExitCode)"
  Write-Host "--- STDOUT ---"
  if (Test-Path "scratch\server-stdout.log") { Get-Content "scratch\server-stdout.log" }
  Write-Host "--- STDERR ---"
  if (Test-Path "scratch\server-stderr.log") { Get-Content "scratch\server-stderr.log" }
} else {
  Write-Host "Server is still running! No crash."
  $p.Kill()
}

# Clean up redirect logs
if (Test-Path "scratch\server-stdout.log") { Remove-Item "scratch\server-stdout.log" -Force }
if (Test-Path "scratch\server-stderr.log") { Remove-Item "scratch\server-stderr.log" -Force }
