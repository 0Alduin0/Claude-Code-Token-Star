[CmdletBinding()]
param(
    [string]$ClaudeSettings = (Join-Path $HOME ".claude\settings.json")
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$StateName = "ghostty-supernova.windows.install.json"
$ClaudeSettings = [System.IO.Path]::GetFullPath($ClaudeSettings)
$statePath = Join-Path (Split-Path -Parent $ClaudeSettings) $StateName

function Read-JsonObject {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{} }
    $text = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{} }
    return $text | ConvertFrom-Json
}

function Write-JsonAtomic {
    param([string]$Path, $Value)
    $temporary = $Path + ".ghostty-supernova.tmp"
    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($temporary, $json + "`n", $Utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Set-ObjectProperty {
    param($Object, [string]$Name, $Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else { $property.Value = $Value }
}

function Remove-HookCommands {
    param($Settings, [string[]]$Commands)
    $hooksProperty = $Settings.PSObject.Properties["hooks"]
    if ($null -eq $hooksProperty) { return }
    $hooks = $hooksProperty.Value
    foreach ($eventName in @("SessionStart", "SessionEnd")) {
        $eventProperty = $hooks.PSObject.Properties[$eventName]
        if ($null -eq $eventProperty) { continue }
        $keptGroups = @()
        foreach ($group in @($eventProperty.Value)) {
            $handlerProperty = $group.PSObject.Properties["hooks"]
            if ($null -eq $handlerProperty) { $keptGroups += $group; continue }
            $keptHandlers = @()
            foreach ($handler in @($handlerProperty.Value)) {
                $commandProperty = $handler.PSObject.Properties["command"]
                if ($null -eq $commandProperty -or $Commands -notcontains [string]$commandProperty.Value) {
                    $keptHandlers += $handler
                }
            }
            if ($keptHandlers.Count -gt 0) {
                Set-ObjectProperty $group "hooks" ([object[]]$keptHandlers)
                $keptGroups += $group
            }
        }
        if ($keptGroups.Count -gt 0) {
            Set-ObjectProperty $hooks $eventName ([object[]]$keptGroups)
        }
        else { $hooks.PSObject.Properties.Remove($eventName) }
    }
    if (@($hooks.PSObject.Properties).Count -eq 0) { $Settings.PSObject.Properties.Remove("hooks") }
}

function Get-VerifiedOverlayProcess {
    param([string]$PidPath)
    if (-not (Test-Path -LiteralPath $PidPath)) { return $null }
    try {
        $record = [System.IO.File]::ReadAllText($PidPath) | ConvertFrom-Json
        $process = Get-Process -Id ([int]$record.pid) -ErrorAction Stop
        $expectedStart = [DateTime]::Parse(
            [string]$record.started_utc,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
        if ([Math]::Abs(($process.StartTime.ToUniversalTime() - $expectedStart).TotalSeconds) -le 1.0) {
            return $process
        }
    }
    catch { }
    return $null
}

$state = Read-JsonObject $statePath
if (@($state.PSObject.Properties).Count -eq 0) {
    Write-Output "Ghostty Supernova for Windows Terminal is not installed."
    exit 0
}

$settings = Read-JsonObject $ClaudeSettings
$command = if ($state.PSObject.Properties["command"]) { [string]$state.command } else { "" }
$commands = @($command) | Where-Object { $_ }
$statusProperty = $settings.PSObject.Properties["statusLine"]
if ($statusProperty -and $statusProperty.Value.PSObject.Properties["command"] -and
    $commands -contains [string]$statusProperty.Value.command) {
    if ($state.had_status_line) {
        Set-ObjectProperty $settings "statusLine" $state.previous_status_line
    }
    else { $settings.PSObject.Properties.Remove("statusLine") }
}
Remove-HookCommands $settings $commands
Write-JsonAtomic $ClaudeSettings $settings

$runtimeRoot = if ($state.PSObject.Properties["runtime_root"]) {
    [System.IO.Path]::GetFullPath([string]$state.runtime_root)
}
else { $null }
$terminalSettings = if ($state.PSObject.Properties["terminal_settings"] -and $state.terminal_settings) {
    [System.IO.Path]::GetFullPath([string]$state.terminal_settings)
}
else { $null }

if ($runtimeRoot) {
    $bridge = Join-Path $runtimeRoot "token-mass-windows.ps1"
    $overlay = Join-Path $runtimeRoot "token-star-overlay.ps1"
    $overlayPid = Join-Path $runtimeRoot "token-star-overlay.pid.json"
    $overlayStop = Join-Path $runtimeRoot "token-star-overlay.stop"
    if (Test-Path -LiteralPath $bridge) {
        $oldOverride = $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS
        try {
            $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $terminalSettings
            & $bridge -Off | Out-Null
        }
        finally { $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $oldOverride }
    }

    $overlayProcess = Get-VerifiedOverlayProcess $overlayPid
    if ($overlayProcess) {
        [System.IO.File]::WriteAllText($overlayStop, "stop`n", $Utf8NoBom)
        foreach ($attempt in 1..30) {
            if (-not (Get-Process -Id $overlayProcess.Id -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 100
        }
        if (Get-Process -Id $overlayProcess.Id -ErrorAction SilentlyContinue) {
            Stop-Process -Id $overlayProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        # Upgrade compatibility for overlays installed before PID records existed.
        foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
            if ($process.Name -in @("powershell.exe", "pwsh.exe") -and $process.CommandLine -and
                $process.CommandLine.IndexOf($overlay, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    }

    foreach ($name in @(
        "profile.json",
        "supernova-windows.hlsl",
        "supernova-windows.generated.hlsl",
        "supernova-windows.generated.hlsl.tmp",
        "token-mass-windows.ps1",
        "token-star-overlay.ps1",
        "token-state.json",
        "token-state.json.tmp",
        "token-star-overlay.pid.json",
        "token-star-overlay.stop",
        "overlay-position.json",
        "overlay-position.json.tmp",
        "overlay.enabled",
        "project-scope.json"
    )) {
        $path = Join-Path $runtimeRoot $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    Get-ChildItem -LiteralPath $runtimeRoot -Filter "token-state.json.*.tmp" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    if ((Test-Path -LiteralPath $runtimeRoot) -and
        (Get-ChildItem -LiteralPath $runtimeRoot -Force | Measure-Object).Count -eq 0) {
        Remove-Item -LiteralPath $runtimeRoot -Force
    }
}

if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
if ($terminalSettings -and (Test-Path -LiteralPath $terminalSettings)) {
    [System.IO.File]::SetLastWriteTimeUtc($terminalSettings, [DateTime]::UtcNow)
}

Write-Output "Removed Claude Code Token Star, its IDE overlay, and Windows Terminal profile."
Write-Output "Close and reopen Windows Terminal to remove the profile from its menu."
