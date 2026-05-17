$dbPath = 'C:\Users\rybek\AppData\Local\Temp\aurum-e2e-162cc6c1\data\database.sqlite'
$binDir = Join-Path $PWD 'bin'
Add-Type -Path (Join-Path $binDir 'System.Data.SQLite.dll')
$conn = New-Object System.Data.SQLite.SQLiteConnection "Data Source=$dbPath;Version=3;"
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT aiConfig FROM users WHERE email='luna@example.com'"
$r = $cmd.ExecuteScalar()
Write-Host "RAW: $r"
