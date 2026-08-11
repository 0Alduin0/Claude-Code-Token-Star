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
$terminalSettings = if ($state.PSObject.Properties["terminal_settings"]) {
    [System.IO.Path]::GetFullPath([string]$state.terminal_settings)
}
else { $null }

if ($runtimeRoot) {
    $bridge = Join-Path $runtimeRoot "token-mass-windows.ps1"
    if (Test-Path -LiteralPath $bridge) {
        $oldOverride = $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS
        try {
            $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $terminalSettings
            & $bridge -Off | Out-Null
        }
        finally { $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $oldOverride }
    }

    foreach ($name in @(
        "profile.json",
        "supernova-windows.hlsl",
        "supernova-windows.generated.hlsl",
        "supernova-windows.generated.hlsl.tmp",
        "token-mass-windows.ps1"
    )) {
        $path = Join-Path $runtimeRoot $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Test-Path -LiteralPath $runtimeRoot) -and
        (Get-ChildItem -LiteralPath $runtimeRoot -Force | Measure-Object).Count -eq 0) {
        Remove-Item -LiteralPath $runtimeRoot -Force
    }
}

if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
if ($terminalSettings -and (Test-Path -LiteralPath $terminalSettings)) {
    [System.IO.File]::SetLastWriteTimeUtc($terminalSettings, [DateTime]::UtcNow)
}

Write-Output "Removed Ghostty Supernova from Claude Code and Windows Terminal."
Write-Output "Close and reopen Windows Terminal to remove the profile from its menu."
