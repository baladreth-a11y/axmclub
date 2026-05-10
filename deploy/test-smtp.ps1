param(
    [string]$HostName = "smtp.gmail.com",
    [int]$Port = 587,
    [string]$User = "axmcamclub@gmail.com",
    [string]$Pass = "", # Paste your App Password here
    [string]$To = "axmcamclub@gmail.com"
)

Write-Host "Testing SMTP connection to $HostName..."
try {
    $client = New-Object Net.Mail.SmtpClient($HostName, $Port)
    $client.EnableSsl = $true
    $client.Timeout = 10000
    if ($User -and $Pass) {
        $client.Credentials = New-Object Net.NetworkCredential($User, $Pass)
    }
    
    $msg = New-Object Net.Mail.MailMessage
    $msg.From = $User
    $msg.To.Add($To)
    $msg.Subject = "AxMclub SMTP Test"
    $msg.Body = "If you see this, SMTP is working correctly on your VPS."
    
    $client.Send($msg)
    Write-Host "SUCCESS: Email sent to $To" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $_" -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    Write-Host "`nTroubleshooting tips:"
    Write-Host "1. Ensure port $Port is open for outbound traffic on your VPS firewall."
    Write-Host "2. If using Gmail, you MUST use an 'App Password', not your regular password."
    Write-Host "3. Check if your VPS provider blocks port 587 or 25 by default (many do)."
}
