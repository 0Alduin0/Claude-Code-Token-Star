[CmdletBinding(DefaultParameterSetName = "StatusLine")]
param(
    [Parameter(ParameterSetName = "StatusLine", ValueFromPipeline = $true)]
    [string]$InputObject,

    [Parameter(ParameterSetName = "Manual", Position = 0, Mandatory = $true)]
    [ValidateRange(0.0, 100.0)]
    [double]$Level,

    [Parameter(ParameterSetName = "Manual")]
    [ValidateRange(0, [long]::MaxValue)]
    [long]$Tokens = -1,

    [Parameter(ParameterSetName = "Manual")]
    [ValidateRange(1, [long]::MaxValue)]
    [long]$WindowSize = 200000,

    [Parameter(ParameterSetName = "Off", Mandatory = $true)]
    [switch]$Off,

    [Parameter(ParameterSetName = "Sweep", Mandatory = $true)]
    [switch]$Sweep,

    [Parameter(ParameterSetName = "Sweep")]
    [ValidateRange(2, 101)]
    [int]$Steps = 31,

    [Parameter(ParameterSetName = "Sweep")]
    [ValidateRange(0.1, 300.0)]
    [double]$Seconds = 15.0,

    [Parameter(ParameterSetName = "Doctor", Mandatory = $true)]
    [switch]$Doctor
)

$ErrorActionPreference = "Stop"
$TemplatePath = Join-Path $PSScriptRoot "supernova-windows.hlsl"
$GeneratedPath = Join-Path $PSScriptRoot "supernova-windows.generated.hlsl"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture

function Get-WindowsTerminalSettingsPath {
    if ($env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS) {
        return [System.IO.Path]::GetFullPath($env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS)
    }

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

function Get-NumberValue {
    param($Value, [double]$Fallback = 0.0)
    if ($null -eq $Value -or $Value -is [bool]) { return $Fallback }
    try {
        $number = [Convert]::ToDouble($Value, $Invariant)
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
            return $Fallback
        }
        return $number
    }
    catch { return $Fallback }
}

function Get-ObjectProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ContextStats {
    param($Data)
    $context = Get-ObjectProperty $Data "context_window"
    $percentageRaw = Get-ObjectProperty $context "used_percentage"
    $tokensRaw = Get-ObjectProperty $context "total_input_tokens"
    $windowRaw = Get-ObjectProperty $context "context_window_size"

    $window = [Math]::Max(0.0, (Get-NumberValue $windowRaw 0.0))
    $hasTokens = $null -ne $tokensRaw
    $tokens = [Math]::Max(0.0, (Get-NumberValue $tokensRaw 0.0))

    if (-not $hasTokens) {
        $usage = Get-ObjectProperty $context "current_usage"
        if ($null -ne $usage) {
            $tokens = 0.0
            foreach ($field in @("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")) {
                $tokens += [Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $usage $field) 0.0))
            }
            $hasTokens = $true
        }
    }

    $hasPercentage = $null -ne $percentageRaw
    $percentage = Get-NumberValue $percentageRaw 0.0
    if (-not $hasPercentage -and $window -gt 0.0 -and $hasTokens) {
        $percentage = 100.0 * $tokens / $window
        $hasPercentage = $true
    }
    $percentage = [Math]::Min(100.0, [Math]::Max(0.0, $percentage))

    if (-not $hasTokens -and $hasPercentage -and $window -gt 0.0) {
        $tokens = $window * $percentage / 100.0
    }
    return [pscustomobject]@{
        Level = $percentage / 100.0
        Tokens = [long][Math]::Round($tokens)
    }
}

function Get-StageName {
    param([double]$Value)
    if ($Value -lt 0.15) { return "RED DWARF" }
    if ($Value -lt 0.35) { return "MAIN SEQUENCE" }
    if ($Value -lt 0.55) { return "BLUE GIANT" }
    if ($Value -lt 0.75) { return "HYPERGIANT" }
    if ($Value -lt 0.90) { return "NEUTRON STAR" }
    return "QUASAR"
}

function Format-TokenCount {
    param([long]$Value)
    if ($Value -ge 1000000) { return ($Value / 1000000.0).ToString("0.00", $Invariant) + "M" }
    if ($Value -ge 1000) { return ($Value / 1000.0).ToString("0.0", $Invariant) + "K" }
    return $Value.ToString($Invariant)
}

function Write-ShaderState {
    param([double]$ContextLevel, [long]$UsedTokens, [bool]$Active)
    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "Windows shader template not found: $TemplatePath"
    }

    $safeLevel = [Math]::Min(1.0, [Math]::Max(0.0, $ContextLevel))
    $massK = [Math]::Min(4095, [Math]::Max(0, [Math]::Round($UsedTokens / 1000.0)))
    $activeNumber = if ($Active) { 1 } else { 0 }
    $header = "#define TOKEN_LEVEL $($safeLevel.ToString('0.######', $Invariant))`n" +
              "#define TOKEN_MASS_K $($massK.ToString($Invariant))`n" +
              "#define TOKEN_ACTIVE $activeNumber`n"
    $template = [System.IO.File]::ReadAllText($TemplatePath)
    $content = $header + $template

    if ((Test-Path -LiteralPath $GeneratedPath) -and
        [System.IO.File]::ReadAllText($GeneratedPath) -eq $content) {
        return
    }

    $temporary = $GeneratedPath + ".tmp"
    [System.IO.File]::WriteAllText($temporary, $content, $Utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $GeneratedPath -Force

    $terminalSettings = Get-WindowsTerminalSettingsPath
    if ($terminalSettings -and (Test-Path -LiteralPath $terminalSettings)) {
        [System.IO.File]::SetLastWriteTimeUtc($terminalSettings, [DateTime]::UtcNow)
    }
}

if ($Doctor) {
    $failed = $false
    if (Test-Path -LiteralPath $TemplatePath) { Write-Output "[OK] HLSL template: $TemplatePath" }
    else { Write-Output "[FAIL] HLSL template: $TemplatePath"; $failed = $true }
    if (Test-Path -LiteralPath $GeneratedPath) { Write-Output "[OK] Generated shader: $GeneratedPath" }
    else { Write-Output "[FAIL] Generated shader: $GeneratedPath"; $failed = $true }
    $terminalSettings = Get-WindowsTerminalSettingsPath
    if ($terminalSettings) { Write-Output "[OK] Windows Terminal settings: $terminalSettings" }
    else { Write-Output "[FAIL] Windows Terminal settings not found"; $failed = $true }
    $terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($terminal) { Write-Output "[OK] Windows Terminal: $($terminal.Source)" }
    else { Write-Output "[FAIL] wt.exe not found"; $failed = $true }
    if ($failed) { exit 1 }
    exit 0
}

if ($Off) {
    Write-ShaderState 0.0 0 $false
    Write-Output "Ghostty Supernova is off for Windows Terminal."
    exit 0
}

if ($Sweep) {
    for ($index = 0; $index -lt $Steps; $index++) {
        $value = $index / [double]($Steps - 1)
        Write-ShaderState $value ([long][Math]::Round(200000 * $value)) $true
        if ($index + 1 -lt $Steps) {
            Start-Sleep -Milliseconds ([int][Math]::Round(1000.0 * $Seconds / ($Steps - 1)))
        }
    }
    Write-Output "Sweep complete at 100% QUASAR."
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq "Manual") {
    $normalized = if ($Level -gt 1.0) { $Level / 100.0 } else { $Level }
    $usedTokens = if ($Tokens -ge 0) { $Tokens } else { [long][Math]::Round($WindowSize * $normalized) }
    Write-ShaderState $normalized $usedTokens $true
    Write-Output "MASS $(Format-TokenCount $usedTokens) - $([Math]::Round($normalized * 100))% - $(Get-StageName $normalized)"
    exit 0
}

$raw = if ($PSBoundParameters.ContainsKey("InputObject")) {
    $InputObject
}
else {
    [Console]::In.ReadToEnd()
}
try {
    $data = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
}
catch {
    $data = [pscustomobject]@{}
}

$eventName = Get-ObjectProperty $data "hook_event_name"
if ($eventName -eq "SessionEnd") {
    Write-ShaderState 0.0 0 $false
    exit 0
}
if ($eventName -eq "SessionStart") {
    Write-ShaderState 0.0 0 $true
    exit 0
}

$stats = Get-ContextStats $data
$contextLevel = [double]$stats.Level
$usedTokens = [long]$stats.Tokens
Write-ShaderState $contextLevel $usedTokens $true
$parts = @(
    "* MASS $(Format-TokenCount $usedTokens) TOKENS",
    "$([Math]::Round($contextLevel * 100))%",
    (Get-StageName $contextLevel)
)
$model = Get-ObjectProperty (Get-ObjectProperty $data "model") "display_name"
if ($model) { $parts += [string]$model }
$escape = [char]27
Write-Output ($escape + "[2m" + ($parts -join " - ") + $escape + "[0m")
