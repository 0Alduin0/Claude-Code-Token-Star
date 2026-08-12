[CmdletBinding()]
param(
    [int]$Port = 4173,
    [switch]$Test
)

$ErrorActionPreference = "Stop"
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) {
    throw "Local preview requires Python 3. Install Python, then run this command again."
}

$url = "http://127.0.0.1:$Port/preview.html"
$pidPath = Join-Path $PSScriptRoot ".preview-server.pid.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    $existing = Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 1
    if ($existing.StatusCode -eq 200) {
        Start-Process $url
        Write-Output "Preview is already running: $url"
        exit 0
    }
}
catch { }
$arguments = if ($python.Name -eq "py.exe") {
    @("-3", "-m", "http.server", $Port, "--bind", "127.0.0.1")
}
else { @("-m", "http.server", $Port, "--bind", "127.0.0.1") }

$server = Start-Process -FilePath $python.Source -ArgumentList $arguments `
    -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
$ownedServer = $null
try {
    foreach ($attempt in 1..30) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 1
            if ($response.StatusCode -eq 200) { break }
        }
        catch { Start-Sleep -Milliseconds 100 }
    }
    if ($attempt -eq 30 -and $response.StatusCode -ne 200) {
        throw "The local preview server did not start."
    }
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $ownedServer = if ($listener) {
        Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    }
    else { $server }
    if (-not $ownedServer) { $ownedServer = $server }
    $serverRecord = [ordered]@{
        schema = 1
        pid = $ownedServer.Id
        started_utc = $ownedServer.StartTime.ToUniversalTime().ToString("o")
        port = $Port
    }
    [IO.File]::WriteAllText($pidPath, ($serverRecord | ConvertTo-Json -Compress) + "`n", $utf8NoBom)
    if ($Test) {
        Write-Output "Preview lifecycle test OK: $url"
    }
    else {
        Start-Process $url
        Write-Output "Preview opened: $url"
        [void](Read-Host "Press Enter here to stop the preview server")
    }
}
finally {
    if ($ownedServer) {
        Stop-Process -Id $ownedServer.Id -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}
