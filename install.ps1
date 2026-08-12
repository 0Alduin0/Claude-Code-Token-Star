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
    return $null
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

function Stop-InstalledOverlay {
    param([string]$RuntimePath)
    $pidPath = Join-Path $RuntimePath "token-star-overlay.pid.json"
    $stopPath = Join-Path $RuntimePath "token-star-overlay.stop"
    $overlayPath = Join-Path $RuntimePath "token-star-overlay.ps1"
    $process = Get-VerifiedOverlayProcess $pidPath
    if ($process) {
        [System.IO.File]::WriteAllText($stopPath, "stop`n", $Utf8NoBom)
        foreach ($attempt in 1..30) {
            if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 100
        }
        if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        return
    }

    # Upgrade compatibility for overlays installed before PID records existed.
    foreach ($legacy in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        if ($legacy.Name -in @("powershell.exe", "pwsh.exe") -and $legacy.CommandLine -and
            $legacy.CommandLine.IndexOf($overlayPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Stop-Process -Id $legacy.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

$TerminalSettings = Find-TerminalSettings
$ClaudeSettings = [System.IO.Path]::GetFullPath($ClaudeSettings)
$RuntimeRoot = [System.IO.Path]::GetFullPath($RuntimeRoot)
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if (-not $PSBoundParameters.ContainsKey("ProjectPath") -and
    (Split-Path -Leaf $ProjectPath) -eq ".claude-token-star") {
    $ProjectPath = Split-Path -Parent $ProjectPath
}
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    throw "Project directory was not found: $ProjectPath"
}

if (-not $SkipVersionCheck) {
    $terminalPackage = Get-AppxPackage Microsoft.WindowsTerminal -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($terminalPackage -and [version]$terminalPackage.Version -lt [version]"1.24.0.0") {
        Write-Warning "Windows Terminal $($terminalPackage.Version) is too old for the optional HLSL profile. The IDE overlay will still work."
    }
}

Stop-InstalledOverlay $RuntimeRoot
[System.IO.Directory]::CreateDirectory($RuntimeRoot) | Out-Null
foreach ($name in @("token-mass-windows.ps1", "token-star-overlay.ps1", "supernova-windows.hlsl")) {
    Copy-Item -LiteralPath (Join-Path $ScriptRoot $name) -Destination (Join-Path $RuntimeRoot $name) -Force
}
[System.IO.File]::WriteAllText(
    (Join-Path $RuntimeRoot "project-scope.json"),
    ([ordered]@{
        schema = 1
        root = $ProjectPath
        name = (Get-Item -LiteralPath $ProjectPath).Name
    } | ConvertTo-Json) + "`n",
    $Utf8NoBom
)
[System.IO.File]::WriteAllText((Join-Path $RuntimeRoot "overlay.enabled"), "enabled`n", $Utf8NoBom)

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
$overlay = Join-Path $RuntimeRoot "token-star-overlay.ps1"
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
Set-ObjectProperty $state "overlay" $overlay
Set-ObjectProperty $state "project_path" $ProjectPath
Set-ObjectProperty $state "overlay_enabled" $true

Remove-HookCommands $settings $commandsToReplace
Set-ObjectProperty $settings "statusLine" ([pscustomobject]@{
    type = "command"
    command = $command
    refreshInterval = 5
})
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
    & $bridge -Off | Out-Null
    & $bridge -Doctor -SkipTerminalCheck:($SkipVersionCheck -or -not $TerminalSettings)
    if ($LASTEXITCODE -ne 0) { throw "Windows bridge doctor failed." }
}
finally {
    $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $oldOverride
}

Write-Output "Installed Claude Code Token Star for Windows."
Write-Output "IDE overlay: $overlay"
Write-Output "Optional Windows Terminal profile: Claude Supernova"
Write-Output "Claude:  $ClaudeSettings"
Write-Output "Runtime: $RuntimeRoot"
if (-not $TerminalSettings) {
    Write-Output "Windows Terminal not found; skipped reload integration. The IDE overlay is fully available."
}
if (-not $NoLaunch) {
    if ($env:GHOSTTY_SUPERNOVA_DISABLE_OVERLAY -ne "1" -and -not (Get-VerifiedOverlayProcess (Join-Path $RuntimeRoot "token-star-overlay.pid.json"))) {
        Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @(
            "-NoLogo", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
            "-File", ('"' + $overlay + '"'),
            "-StatePath", ('"' + (Join-Path $RuntimeRoot "token-state.json") + '"'),
            "-PidPath", ('"' + (Join-Path $RuntimeRoot "token-star-overlay.pid.json") + '"'),
            "-StopPath", ('"' + (Join-Path $RuntimeRoot "token-star-overlay.stop") + '"'),
            "-PositionPath", ('"' + (Join-Path $RuntimeRoot "overlay-position.json") + '"')
        ) | Out-Null
    }
    Write-Output "Overlay is ready. The currently running Claude session will attach on its next status refresh."
}
else {
    Write-Output "Automatic overlay launch skipped. No new Claude session was started."
}
