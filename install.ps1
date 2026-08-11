[CmdletBinding()]
param(
    [string]$ClaudeSettings = (Join-Path $HOME ".claude\settings.json"),
    [string]$TerminalSettings,
    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\GhosttySupernova"),
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$SkipVersionCheck,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateName = "ghostty-supernova.windows.install.json"

function Find-TerminalSettings {
    if ($TerminalSettings) { return [System.IO.Path]::GetFullPath($TerminalSettings) }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "Windows Terminal settings.json was not found. Install Windows Terminal 1.24 or newer first."
}

function Read-JsonObject {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{} }
    $text = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{} }
    try { $value = $text | ConvertFrom-Json }
    catch { throw "$Label is not valid JSON: $Path`n$($_.Exception.Message)" }
    if ($null -eq $value -or $value -is [array] -or $value -isnot [psobject]) {
        throw "$Label root must be a JSON object: $Path"
    }
    return $value
}

function Write-JsonAtomic {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = $Path + ".ghostty-supernova.tmp"
    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($temporary, $json + "`n", $Utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-TextAtomic {
    param([string]$Path, [string]$Text)
    $temporary = $Path + ".ghostty-supernova.tmp"
    [System.IO.File]::WriteAllText($temporary, $Text, $Utf8NoBom)
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

function Test-HookGroupCommand {
    param($Group, [string]$Command)
    if ($null -eq $Group) { return $false }
    $handlersProperty = $Group.PSObject.Properties["hooks"]
    if ($null -eq $handlersProperty) { return $false }
    foreach ($handler in @($handlersProperty.Value)) {
        if ($handler.PSObject.Properties["command"] -and $handler.command -eq $Command) {
            return $true
        }
    }
    return $false
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
        if ($keptGroups.Count -gt 0) { Set-ObjectProperty $hooks $eventName ([object[]]$keptGroups) }
        else { $hooks.PSObject.Properties.Remove($eventName) }
    }
    if (@($hooks.PSObject.Properties).Count -eq 0) { $Settings.PSObject.Properties.Remove("hooks") }
}

$TerminalSettings = Find-TerminalSettings
$ClaudeSettings = [System.IO.Path]::GetFullPath($ClaudeSettings)
$RuntimeRoot = [System.IO.Path]::GetFullPath($RuntimeRoot)

if (-not $SkipVersionCheck) {
    $terminalPackage = Get-AppxPackage Microsoft.WindowsTerminal -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $terminalPackage) { throw "Windows Terminal is not installed." }
    if ([version]$terminalPackage.Version -lt [version]"1.24.0.0") {
        throw "Windows Terminal 1.24+ is required; found $($terminalPackage.Version)."
    }
}

[System.IO.Directory]::CreateDirectory($RuntimeRoot) | Out-Null
foreach ($name in @("token-mass-windows.ps1", "supernova-windows.hlsl")) {
    Copy-Item -LiteralPath (Join-Path $ScriptRoot $name) -Destination (Join-Path $RuntimeRoot $name) -Force
}

$generatedShader = Join-Path $RuntimeRoot "supernova-windows.generated.hlsl"
$profile = [ordered]@{
    profiles = @(
        [ordered]@{
            guid = "{8f3e7344-11ef-5c09-a645-9b8c2c3f6b63}"
            name = "Claude Supernova"
            commandline = 'powershell.exe -NoLogo -NoExit -Command "claude"'
            startingDirectory = "%USERPROFILE%"
            "experimental.pixelShaderPath" = $generatedShader
        }
    )
}
[System.IO.File]::WriteAllText(
    (Join-Path $RuntimeRoot "profile.json"),
    ($profile | ConvertTo-Json -Depth 20) + "`n",
    $Utf8NoBom
)

$settings = Read-JsonObject $ClaudeSettings "Claude settings"
$statePath = Join-Path (Split-Path -Parent $ClaudeSettings) $StateName
$state = Read-JsonObject $statePath "Install state"
$legacyStatePath = Join-Path (Split-Path -Parent $ClaudeSettings) "ghostty-supernova.install.json"
$legacyState = Read-JsonObject $legacyStatePath "Legacy install state"
$bridge = Join-Path $RuntimeRoot "token-mass-windows.ps1"
$command = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$bridge`""
$commandsToReplace = @($command)
if ($state.PSObject.Properties["command"] -and $state.command) {
    $commandsToReplace += [string]$state.command
}
$legacyCommand = if ($legacyState.PSObject.Properties["command"] -and $legacyState.command) {
    [string]$legacyState.command
}
else { $null }
if ($legacyCommand) { $commandsToReplace += $legacyCommand }

if (@($state.PSObject.Properties).Count -eq 0) {
    $currentStatusCommand = if ($settings.PSObject.Properties["statusLine"] -and
        $settings.statusLine.PSObject.Properties["command"]) {
        [string]$settings.statusLine.command
    }
    else { $null }
    $migratingLegacy = $legacyCommand -and $currentStatusCommand -eq $legacyCommand
    if ($migratingLegacy) {
        $hadStatusLine = [bool]$legacyState.had_status_line
        $previousStatusLine = $legacyState.previous_status_line
    }
    else {
        $hadStatusLine = $null -ne $settings.PSObject.Properties["statusLine"]
        $previousStatusLine = if ($hadStatusLine) { $settings.statusLine } else { $null }
    }
    $state = [pscustomobject]@{
        schema = 1
        had_status_line = $hadStatusLine
        previous_status_line = $previousStatusLine
    }
}
Set-ObjectProperty $state "command" $command
Set-ObjectProperty $state "claude_settings" $ClaudeSettings
Set-ObjectProperty $state "terminal_settings" $TerminalSettings
Set-ObjectProperty $state "runtime_root" $RuntimeRoot

Remove-HookCommands $settings $commandsToReplace
Set-ObjectProperty $settings "statusLine" ([pscustomobject]@{ type = "command"; command = $command })
$hooksProperty = $settings.PSObject.Properties["hooks"]
if ($null -eq $hooksProperty) {
    $hooks = [pscustomobject]@{}
    Set-ObjectProperty $settings "hooks" $hooks
}
else { $hooks = $hooksProperty.Value }

foreach ($eventName in @("SessionStart", "SessionEnd")) {
    $eventProperty = $hooks.PSObject.Properties[$eventName]
    $eventHooks = if ($null -eq $eventProperty) { @() } else { @($eventProperty.Value) }
    $alreadyInstalled = $false
    foreach ($group in $eventHooks) {
        if (Test-HookGroupCommand $group $command) { $alreadyInstalled = $true; break }
    }
    if (-not $alreadyInstalled) {
        $eventHooks += [pscustomobject]@{
            hooks = @([pscustomobject]@{ type = "command"; command = $command; timeout = 5 })
        }
    }
    Set-ObjectProperty $hooks $eventName ([object[]]$eventHooks)
}

Write-JsonAtomic $ClaudeSettings $settings
Write-JsonAtomic $statePath $state

if ($legacyCommand -and (Test-Path -LiteralPath $legacyStatePath)) {
    if ($legacyState.PSObject.Properties["ghostty_config"] -and
        (Test-Path -LiteralPath ([string]$legacyState.ghostty_config))) {
        $legacyConfigPath = [string]$legacyState.ghostty_config
        $legacyConfig = [System.IO.File]::ReadAllText($legacyConfigPath)
        $legacyPattern = "(?ms)(?:\r?\n)?\# >>> ghostty-supernova >>>.*?\# <<< ghostty-supernova <<<(?:\r?\n)?"
        $cleanConfig = [regex]::Replace($legacyConfig, $legacyPattern, "`n").Trim()
        Write-TextAtomic $legacyConfigPath $(if ($cleanConfig) { $cleanConfig + "`n" } else { "" })
    }
    Remove-Item -LiteralPath $legacyStatePath -Force
}

$oldOverride = $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS
try {
    $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $TerminalSettings
    & $bridge -Level 0 -Tokens 0 | Out-Null
    & $bridge -Doctor
    if ($LASTEXITCODE -ne 0) { throw "Windows bridge doctor failed." }
}
finally {
    $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $oldOverride
}

Write-Output "Installed Ghostty Supernova for Windows Terminal."
Write-Output "Profile: Claude Supernova"
Write-Output "Claude:  $ClaudeSettings"
Write-Output "Runtime: $RuntimeRoot"
if (-not $NoLaunch) {
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        throw "Project directory was not found: $ProjectPath"
    }
    Write-Output "Opening Claude Supernova in: $ProjectPath"
    & wt.exe -w new -p "Claude Supernova" -d $ProjectPath
    if ($LASTEXITCODE -ne 0) { throw "Windows Terminal could not launch Claude Supernova." }
}
else {
    Write-Output "Automatic launch skipped."
}
