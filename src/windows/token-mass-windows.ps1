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

    [Parameter(ParameterSetName = "On", Mandatory = $true)]
    [switch]$On,

    [Parameter(ParameterSetName = "Reset", Mandatory = $true)]
    [switch]$Reset,

    [Parameter(ParameterSetName = "Sweep", Mandatory = $true)]
    [switch]$Sweep,

    [Parameter(ParameterSetName = "Sweep")]
    [ValidateRange(2, 101)]
    [int]$Steps = 31,

    [Parameter(ParameterSetName = "Sweep")]
    [ValidateRange(0.1, 300.0)]
    [double]$Seconds = 15.0,

    [Parameter(ParameterSetName = "Doctor", Mandatory = $true)]
    [switch]$Doctor,

    [Parameter(ParameterSetName = "Doctor")]
    [switch]$SkipTerminalCheck
)

$ErrorActionPreference = "Stop"
$TemplatePath = Join-Path $PSScriptRoot "supernova-windows.hlsl"
$GeneratedPath = Join-Path $PSScriptRoot "supernova-windows.generated.hlsl"
$TokenStatePath = Join-Path $PSScriptRoot "token-state.json"
$OverlayPath = Join-Path $PSScriptRoot "token-star-overlay.ps1"
$OverlayEnabledPath = Join-Path $PSScriptRoot "overlay.enabled"
$OverlayPidPath = Join-Path $PSScriptRoot "token-star-overlay.pid.json"
$OverlayStopPath = Join-Path $PSScriptRoot "token-star-overlay.stop"
$OverlayPositionPath = Join-Path $PSScriptRoot "overlay-position.json"
$SessionStateRoot = Join-Path $PSScriptRoot "sessions"
$ProjectScopePath = Join-Path $PSScriptRoot "project-scope.json"
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

function Get-ProjectScope {
    if (-not (Test-Path -LiteralPath $ProjectScopePath)) { return $null }
    try { return [System.IO.File]::ReadAllText($ProjectScopePath) | ConvertFrom-Json }
    catch { return $null }
}

function Test-PathInProject {
    param([string]$CandidatePath)
    $scope = Get-ProjectScope
    if ($null -eq $scope -or -not $scope.root) { return $true }
    if ([string]::IsNullOrWhiteSpace($CandidatePath)) { return $false }
    try {
        $trimChars = [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $root = [System.IO.Path]::GetFullPath([string]$scope.root).TrimEnd($trimChars)
        $candidate = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd($trimChars)
        if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        return $candidate.StartsWith(
            $root + [System.IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        )
    }
    catch { return $false }
}

function Get-InvocationProjectPath {
    param($Data)
    $workspace = Get-ObjectProperty $Data "workspace"
    foreach ($candidate in @(
        (Get-ObjectProperty $workspace "project_dir"),
        (Get-ObjectProperty $workspace "current_dir"),
        (Get-ObjectProperty $Data "cwd")
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }
    }
    return (Get-Location).Path
}

function Get-SessionId {
    param($Data)
    $direct = Get-ObjectProperty $Data "session_id"
    if (-not [string]::IsNullOrWhiteSpace([string]$direct)) { return [string]$direct }
    $session = Get-ObjectProperty $Data "session"
    $nested = Get-ObjectProperty $session "id"
    if (-not [string]::IsNullOrWhiteSpace([string]$nested)) { return [string]$nested }
    return ""
}

function Get-SessionStatePath {
    param([string]$SessionId)
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $null }
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SessionId))
    }
    finally { $algorithm.Dispose() }
    $name = (($bytes[0..15] | ForEach-Object { $_.ToString("x2") }) -join "") + ".json"
    return Join-Path $SessionStateRoot $name
}

function Write-SessionState {
    param($Data, $Stats)
    $sessionId = Get-SessionId $Data
    $path = Get-SessionStatePath $sessionId
    if (-not $path) { return }
    [System.IO.Directory]::CreateDirectory($SessionStateRoot) | Out-Null
    $record = [ordered]@{
        schema = 1
        session_id = $sessionId
        updated_utc = [DateTime]::UtcNow.ToString("o", $Invariant)
        level = [double]$Stats.Level
        tokens = [long]$Stats.Tokens
        window_size = [long]$Stats.WindowSize
        fresh_input = [long]$Stats.FreshInput
        cache_creation = [long]$Stats.CacheCreation
        cache_read = [long]$Stats.CacheRead
        output_tokens = [long]$Stats.OutputTokens
        five_hour_used = [double]$Stats.FiveHourUsed
        five_hour_resets_at = [long]$Stats.FiveHourResetsAt
        seven_day_used = [double]$Stats.SevenDayUsed
        seven_day_resets_at = [long]$Stats.SevenDayResetsAt
        model = [string]$Stats.Model
        effort = [string]$Stats.Effort
    }
    $temporary = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json -Compress) + "`n", $Utf8NoBom)
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Remove-SessionState {
    param($Data)
    $path = Get-SessionStatePath (Get-SessionId $Data)
    if ($path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Get-HighestSessionStats {
    if (-not (Test-Path -LiteralPath $SessionStateRoot -PathType Container)) { return $null }
    $cutoff = [DateTime]::UtcNow.AddMinutes(-10)
    $candidates = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $SessionStateRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try {
            $record = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
            $updated = [DateTime]::Parse(
                [string]$record.updated_utc,
                $Invariant,
                [Globalization.DateTimeStyles]::RoundtripKind
            ).ToUniversalTime()
            if ($updated -lt $cutoff) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                continue
            }
            $candidates += $record
        }
        catch { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
    }
    if ($candidates.Count -eq 0) { return $null }
    $selected = $candidates | Sort-Object @{ Expression = { [long]$_.tokens }; Descending = $true }, `
        @{ Expression = { [double]$_.level }; Descending = $true }, `
        @{ Expression = { [string]$_.updated_utc }; Descending = $true } | Select-Object -First 1
    return [pscustomobject]@{
        Level = [double]$selected.level
        Tokens = [long]$selected.tokens
        WindowSize = [long]$selected.window_size
        FreshInput = [long]$selected.fresh_input
        CacheCreation = [long]$selected.cache_creation
        CacheRead = [long]$selected.cache_read
        OutputTokens = [long]$selected.output_tokens
        FiveHourUsed = [double]$selected.five_hour_used
        FiveHourResetsAt = [long]$selected.five_hour_resets_at
        SevenDayUsed = [double]$selected.seven_day_used
        SevenDayResetsAt = [long]$selected.seven_day_resets_at
        Model = [string]$selected.model
        Effort = [string]$selected.effort
        SessionCount = [int]$candidates.Count
    }
}

function Get-ContextStats {
    param($Data)
    $context = Get-ObjectProperty $Data "context_window"
    $percentageRaw = Get-ObjectProperty $context "used_percentage"
    $tokensRaw = Get-ObjectProperty $context "total_input_tokens"
    $windowRaw = Get-ObjectProperty $context "context_window_size"
    $outputRaw = Get-ObjectProperty $context "total_output_tokens"
    $usage = Get-ObjectProperty $context "current_usage"
    $freshInput = [Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $usage "input_tokens") 0.0))
    $cacheCreation = [Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $usage "cache_creation_input_tokens") 0.0))
    $cacheRead = [Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $usage "cache_read_input_tokens") 0.0))
    $outputTokens = [Math]::Max(0.0, (Get-NumberValue $outputRaw (Get-NumberValue (Get-ObjectProperty $usage "output_tokens") 0.0)))
    $rateLimits = Get-ObjectProperty $Data "rate_limits"
    $fiveHour = Get-ObjectProperty $rateLimits "five_hour"
    $sevenDay = Get-ObjectProperty $rateLimits "seven_day"
    $modelData = Get-ObjectProperty $Data "model"
    $model = Get-ObjectProperty $modelData "display_name"
    if ([string]::IsNullOrWhiteSpace([string]$model)) {
        $model = Get-ObjectProperty $modelData "id"
    }
    $effort = Get-ObjectProperty (Get-ObjectProperty $Data "effort") "level"

    $window = [Math]::Max(0.0, (Get-NumberValue $windowRaw 0.0))
    $hasTokens = $null -ne $tokensRaw
    $tokens = [Math]::Max(0.0, (Get-NumberValue $tokensRaw 0.0))

    if (-not $hasTokens) {
        if ($null -ne $usage) {
            $tokens = $freshInput + $cacheCreation + $cacheRead
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
        WindowSize = [long][Math]::Round($window)
        FreshInput = [long][Math]::Round($freshInput)
        CacheCreation = [long][Math]::Round($cacheCreation)
        CacheRead = [long][Math]::Round($cacheRead)
        OutputTokens = [long][Math]::Round($outputTokens)
        FiveHourUsed = Get-NumberValue (Get-ObjectProperty $fiveHour "used_percentage") -1.0
        FiveHourResetsAt = [long][Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $fiveHour "resets_at") 0.0))
        SevenDayUsed = Get-NumberValue (Get-ObjectProperty $sevenDay "used_percentage") -1.0
        SevenDayResetsAt = [long][Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $sevenDay "resets_at") 0.0))
        Model = if ($model) { [string]$model } else { "" }
        Effort = if ($effort) { [string]$effort } else { "" }
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

function Write-TokenState {
    param([double]$ContextLevel, [long]$UsedTokens, [bool]$Active, $Breakdown = $null)
    $safeLevel = [Math]::Min(1.0, [Math]::Max(0.0, $ContextLevel))
    $scope = Get-ProjectScope
    $windowSize = if ($Breakdown) { [Math]::Max(0L, [long]$Breakdown.WindowSize) } else { 0L }
    $details = [ordered]@{
        total_input_tokens = [Math]::Max(0L, $UsedTokens)
        total_output_tokens = if ($Breakdown) { [Math]::Max(0L, [long]$Breakdown.OutputTokens) } else { 0L }
        fresh_input_tokens = if ($Breakdown) { [Math]::Max(0L, [long]$Breakdown.FreshInput) } else { 0L }
        cache_creation_input_tokens = if ($Breakdown) { [Math]::Max(0L, [long]$Breakdown.CacheCreation) } else { 0L }
        cache_read_input_tokens = if ($Breakdown) { [Math]::Max(0L, [long]$Breakdown.CacheRead) } else { 0L }
        context_window_size = $windowSize
        remaining_tokens = if ($windowSize -gt 0) { [Math]::Max(0L, $windowSize - $UsedTokens) } else { 0L }
    }
    $rateLimits = [ordered]@{
        five_hour = [ordered]@{
            used_percentage = if ($Breakdown) { Get-NumberValue (Get-ObjectProperty $Breakdown "FiveHourUsed") -1.0 } else { -1.0 }
            resets_at = if ($Breakdown) { [long][Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $Breakdown "FiveHourResetsAt") 0.0)) } else { 0L }
        }
        seven_day = [ordered]@{
            used_percentage = if ($Breakdown) { Get-NumberValue (Get-ObjectProperty $Breakdown "SevenDayUsed") -1.0 } else { -1.0 }
            resets_at = if ($Breakdown) { [long][Math]::Max(0.0, (Get-NumberValue (Get-ObjectProperty $Breakdown "SevenDayResetsAt") 0.0)) } else { 0L }
        }
    }
    $state = [ordered]@{
        schema = 3
        level = $safeLevel
        tokens = [Math]::Max(0L, $UsedTokens)
        active = $Active
        stage = Get-StageName $safeLevel
        project_root = if ($scope) { [string]$scope.root } else { "" }
        project_name = if ($scope) { [string]$scope.name } else { "" }
        model = if ($Breakdown) { [string](Get-ObjectProperty $Breakdown "Model") } else { "" }
        effort = if ($Breakdown) { [string](Get-ObjectProperty $Breakdown "Effort") } else { "" }
        active_sessions = if ($Breakdown) {
            [Math]::Max(1, [int](Get-NumberValue (Get-ObjectProperty $Breakdown "SessionCount") 1.0))
        }
        elseif ($Active) { 1 } else { 0 }
        breakdown = $details
        rate_limits = $rateLimits
        updated_utc = [DateTime]::UtcNow.ToString("o", $Invariant)
    }
    $temporary = $TokenStatePath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [System.IO.File]::WriteAllText(
            $temporary,
            ($state | ConvertTo-Json -Depth 5 -Compress) + "`n",
            $Utf8NoBom
        )
        Move-Item -LiteralPath $temporary -Destination $TokenStatePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OverlayProcess {
    if (-not (Test-Path -LiteralPath $OverlayPidPath)) { return $null }
    try {
        $record = [System.IO.File]::ReadAllText($OverlayPidPath) | ConvertFrom-Json
        $process = Get-Process -Id ([int]$record.pid) -ErrorAction Stop
        $expectedStart = [DateTime]::Parse(
            [string]$record.started_utc,
            $Invariant,
            [Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        if ([Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -le 1.0) {
            return $process
        }
    }
    catch { }
    return $null
}

function Start-OverlayIfNeeded {
    if ($env:GHOSTTY_SUPERNOVA_DISABLE_OVERLAY -eq "1" -or
        -not (Test-Path -LiteralPath $OverlayEnabledPath) -or
        -not (Test-Path -LiteralPath $OverlayPath) -or
        (Get-OverlayProcess)) {
        return
    }
    Remove-Item -LiteralPath $OverlayStopPath -Force -ErrorAction SilentlyContinue
    try {
        $quotedOverlayPath = '"' + $OverlayPath + '"'
        $quotedStatePath = '"' + $TokenStatePath + '"'
        $quotedPidPath = '"' + $OverlayPidPath + '"'
        $quotedStopPath = '"' + $OverlayStopPath + '"'
        $quotedPositionPath = '"' + $OverlayPositionPath + '"'
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $quotedOverlayPath,
            "-StatePath", $quotedStatePath,
            "-PidPath", $quotedPidPath,
            "-StopPath", $quotedStopPath,
            "-PositionPath", $quotedPositionPath
        ) | Out-Null
    }
    catch {
        # The terminal shader and status line must keep working if the optional
        # desktop overlay cannot start.
    }
}

function Clear-SessionStates {
    if (-not (Test-Path -LiteralPath $SessionStateRoot -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $SessionStateRoot -File -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $SessionStateRoot -Force -ErrorAction SilentlyContinue
}

function Stop-Overlay {
    $process = Get-OverlayProcess
    if (-not $process) { return }
    [System.IO.File]::WriteAllText($OverlayStopPath, "stop`n", $Utf8NoBom)
    foreach ($attempt in 1..20) {
        if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 100
    }
}

function Write-ShaderState {
    param([double]$ContextLevel, [long]$UsedTokens, [bool]$Active, $Breakdown = $null)
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

    Write-TokenState $safeLevel $UsedTokens $Active $Breakdown
    if ($Active) { Start-OverlayIfNeeded }

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
    if (Test-Path -LiteralPath $TokenStatePath) { Write-Output "[OK] Shared token state: $TokenStatePath" }
    else { Write-Output "[FAIL] Shared token state: $TokenStatePath"; $failed = $true }
    $scope = Get-ProjectScope
    if ($scope -and $scope.root -and (Test-Path -LiteralPath ([string]$scope.root) -PathType Container)) {
        Write-Output "[OK] Project scope: $($scope.root)"
    }
    else { Write-Output "[FAIL] Project scope is missing or invalid: $ProjectScopePath"; $failed = $true }
    if (Test-Path -LiteralPath $OverlayEnabledPath) {
        if (Test-Path -LiteralPath $OverlayPath) { Write-Output "[OK] IDE overlay: installed and enabled" }
        else { Write-Output "[FAIL] IDE overlay is enabled but its script is missing"; $failed = $true }
    }
    else { Write-Output "[SKIP] IDE overlay: disabled" }
    $terminalSettings = Get-WindowsTerminalSettingsPath
    if ($terminalSettings) { Write-Output "[OK] Optional Windows Terminal settings: $terminalSettings" }
    else { Write-Output "[SKIP] Optional Windows Terminal settings not found" }
    if ($SkipTerminalCheck) { Write-Output "[SKIP] Windows Terminal executable check" }
    else {
        $terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
        if ($terminal) { Write-Output "[OK] Optional Windows Terminal: $($terminal.Source)" }
        else { Write-Output "[SKIP] Optional Windows Terminal not found" }
    }
    if ($failed) { exit 1 }
    exit 0
}

if ($Reset) {
    Clear-SessionStates
    Write-ShaderState 0.0 0 $false
    exit 0
}

if ($Off) {
    Remove-Item -LiteralPath $OverlayEnabledPath -Force -ErrorAction SilentlyContinue
    Clear-SessionStates
    Write-ShaderState 0.0 0 $false
    Stop-Overlay
    Write-Output "Claude Code Token Star is off. Run the on command to show it again."
    exit 0
}

if ($On) {
    [System.IO.File]::WriteAllText($OverlayEnabledPath, "enabled`n", $Utf8NoBom)
    Remove-Item -LiteralPath $OverlayStopPath -Force -ErrorAction SilentlyContinue
    Start-OverlayIfNeeded
    Write-Output "Claude Code Token Star is on. It will appear on the next Claude status refresh."
    exit 0
}

if ($Sweep) {
    if (-not (Test-PathInProject (Get-Location).Path)) {
        Write-ShaderState 0.0 0 $false
        Write-Output "Ghostty Supernova is inactive outside its configured project."
        exit 0
    }
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
    if (-not (Test-PathInProject (Get-Location).Path)) {
        Write-ShaderState 0.0 0 $false
        Write-Output "Ghostty Supernova is inactive outside its configured project."
        exit 0
    }
    $normalized = if ($Level -gt 1.0) { $Level / 100.0 } else { $Level }
    $usedTokens = if ($Tokens -ge 0) { $Tokens } else { [long][Math]::Round($WindowSize * $normalized) }
    $manualBreakdown = [pscustomobject]@{ WindowSize = $WindowSize; FreshInput = $usedTokens; CacheCreation = 0L; CacheRead = 0L; OutputTokens = 0L; FiveHourUsed = -1.0; FiveHourResetsAt = 0L; SevenDayUsed = -1.0; SevenDayResetsAt = 0L }
    Write-ShaderState $normalized $usedTokens $true $manualBreakdown
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

if (-not (Test-PathInProject (Get-InvocationProjectPath $data))) {
    Write-ShaderState 0.0 0 $false
    exit 0
}

$eventName = Get-ObjectProperty $data "hook_event_name"
if ($eventName -eq "SessionEnd") {
    Remove-SessionState $data
    $remaining = Get-HighestSessionStats
    if ($remaining) { Write-ShaderState ([double]$remaining.Level) ([long]$remaining.Tokens) $true $remaining }
    else { Write-ShaderState 0.0 0 $false }
    exit 0
}
if ($eventName -eq "SessionStart") {
    $started = Get-ContextStats $data
    Write-SessionState $data $started
    $selected = Get-HighestSessionStats
    if (-not $selected) { $selected = $started }
    Write-ShaderState ([double]$selected.Level) ([long]$selected.Tokens) $true $selected
    exit 0
}

$stats = Get-ContextStats $data
$contextLevel = [double]$stats.Level
$usedTokens = [long]$stats.Tokens
Write-SessionState $data $stats
$selected = Get-HighestSessionStats
if (-not $selected) { $selected = $stats }
Write-ShaderState ([double]$selected.Level) ([long]$selected.Tokens) $true $selected
$massUsage = Format-TokenCount $usedTokens
if ([long]$stats.WindowSize -gt 0) {
    $massUsage += " / $(Format-TokenCount ([long]$stats.WindowSize))"
}
$parts = @(
    "* MASS $massUsage TOKENS",
    "$([Math]::Round($contextLevel * 100))%",
    (Get-StageName $contextLevel)
)
$model = [string]$stats.Model
if ($model) { $parts += $model }
$effort = [string]$stats.Effort
if ($effort) { $parts += ($effort.ToUpperInvariant() + " effort") }
$escape = [char]27
Write-Output ($escape + "[2m" + ($parts -join " - ") + $escape + "[0m")
