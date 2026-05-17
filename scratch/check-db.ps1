Add-Type -Path 'c:\Users\rybek\axmclub\bin\System.Data.SQLite.dll'
$conn = New-Object System.Data.SQLite.SQLiteConnection 'Data Source=c:\Users\rybek\axmclub\data\database.sqlite;Version=3;'
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = 'PRAGMA table_info(stats)'
$r = $cmd.ExecuteReader()
while ($r.Read()) {
    Write-Host "Column: $($r.GetValue(1)) ($($r.GetValue(2)))"
}
$r.Close()
$conn.Close()
