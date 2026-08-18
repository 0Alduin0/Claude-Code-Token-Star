[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = "",
    [long]$Tokens = -1,
    [long]$WindowSize = 200000,
    [string]$ClaudeSettings
)

$ErrorActionPreference = "Stop"
$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Split-Path -Parent $toolsRoot
$sourceBridge = Join-Path $sourceRoot "src\windows\token-mass-windows.ps1"
$sourceLayout = Test-Path -LiteralPath $sourceBridge
$projectRoot = if ($sourceLayout) { $sourceRoot } else { Split-Path -Parent $toolsRoot }
if ([string]::IsNullOrWhiteSpace($ClaudeSettings)) {
    $ClaudeSettings = Join-Path $projectRoot ".claude\settings.local.json"
}
$statePath = Join-Path (Split-Path -Parent ([System.IO.Path]::GetFullPath($ClaudeSettings))) "ghostty-supernova.windows.install.json"
$installed = $null
if (Test-Path -LiteralPath $statePath) {
    try {
        $state = [System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        if ($state.runtime_root) {
            $installed = Join-Path ([string]$state.runtime_root) "token-mass-windows.ps1"
        }
    }
    catch { }
}
if (-not $installed) {
    $installed = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\GhosttySupernova\token-mass-windows.ps1"
}
$local = Join-Path $toolsRoot "token-mass-windows.ps1"
$bridge = if (Test-Path -LiteralPath $installed) { $installed } elseif ($sourceLayout) { $sourceBridge } else { $local }
if (-not (Test-Path -LiteralPath $bridge)) { throw "Windows token bridge was not found." }

switch ($Action.ToLowerInvariant()) {
    "sweep" { & $bridge -Sweep; exit $LASTEXITCODE }
    "on" { & $bridge -On; exit $LASTEXITCODE }
    "off" { & $bridge -Off; exit $LASTEXITCODE }
    "doctor" { & $bridge -Doctor; exit $LASTEXITCODE }
    "" {
        Write-Output "Usage: .\token-test.ps1 LEVEL|sweep|on|off|doctor [-Tokens N]"
        exit 2
    }
    default {
        $level = 0.0
        if (-not [double]::TryParse($Action.TrimEnd('%'), [ref]$level)) {
            throw "LEVEL must be a number such as 82, 82%, or 0.82."
        }
        if ($Action.EndsWith("%")) { $level = $level / 100.0 }
        $arguments = @{ Level = $level; WindowSize = $WindowSize }
        if ($Tokens -ge 0) { $arguments.Tokens = $Tokens }
        & $bridge @arguments
        exit $LASTEXITCODE
    }
}
