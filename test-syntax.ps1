$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("c:\Users\rybek\axmclub\server.ps1", [ref]$null, [ref]$errors)
if ($errors) {
    foreach ($e in $errors) {
        Write-Host "Line $($e.Extent.StartLineNumber): $($e.Message)"
    }
    exit 1
} else {
    Write-Host 'Syntax OK'
}
