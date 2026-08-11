$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TemporaryRoot = Join-Path $env:TEMP ("ghostty-supernova-test-" + [guid]::NewGuid().ToString("N"))
$ClaudeSettings = Join-Path $TemporaryRoot ".claude\settings.json"
$TerminalSettings = Join-Path $TemporaryRoot "terminal\settings.json"
$RuntimeRoot = Join-Path $TemporaryRoot "runtime"
$LegacyState = Join-Path $TemporaryRoot ".claude\ghostty-supernova.install.json"
$LegacyGhosttyConfig = Join-Path $TemporaryRoot "ghostty\config.ghostty"
$LegacyCommand = "python C:\legacy\ghostty-supernova\token-mass.py"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $ClaudeSettings)) | Out-Null
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $TerminalSettings)) | Out-Null
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $LegacyGhosttyConfig)) | Out-Null
    $initialSettings = [ordered]@{
        permissions = [ordered]@{ allow = @("Read") }
        statusLine = [ordered]@{ type = "command"; command = $LegacyCommand }
        hooks = [ordered]@{
            PreToolUse = @()
            SessionStart = @([ordered]@{ hooks = @([ordered]@{ type = "command"; command = $LegacyCommand; timeout = 5 }) })
            SessionEnd = @([ordered]@{ hooks = @([ordered]@{ type = "command"; command = $LegacyCommand; timeout = 5 }) })
        }
    }
    [System.IO.File]::WriteAllText(
        $ClaudeSettings,
        ($initialSettings | ConvertTo-Json -Depth 20),
        $Utf8NoBom
    )
    [System.IO.File]::WriteAllText($TerminalSettings, '{}', $Utf8NoBom)
    [System.IO.File]::WriteAllText(
        $LegacyGhosttyConfig,
        "font-size = 13`n# >>> ghostty-supernova >>>`ncustom-shader = old.glsl`n# <<< ghostty-supernova <<<`n",
        $Utf8NoBom
    )
    $legacyInstall = [ordered]@{
        schema = 1
        had_status_line = $true
        previous_status_line = [ordered]@{ type = "command"; command = "bash ~/.claude/statusline-command.sh" }
        command = $LegacyCommand
        ghostty_config = $LegacyGhosttyConfig
    }
    [System.IO.File]::WriteAllText($LegacyState, ($legacyInstall | ConvertTo-Json -Depth 20), $Utf8NoBom)

    foreach ($file in @("install.ps1", "uninstall.ps1", "token-test.ps1", "token-mass-windows.ps1")) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $Root $file), [ref]$tokens, [ref]$parseErrors
        ) | Out-Null
        Assert-True ($parseErrors.Count -eq 0) "$file has PowerShell syntax errors"
    }

    & (Join-Path $Root "install.ps1") `
        -ClaudeSettings $ClaudeSettings `
        -TerminalSettings $TerminalSettings `
        -RuntimeRoot $RuntimeRoot `
        -SkipVersionCheck | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "installer returned a failure"

    # Reinstall must not duplicate hooks or overwrite the original backup.
    & (Join-Path $Root "install.ps1") `
        -ClaudeSettings $ClaudeSettings `
        -TerminalSettings $TerminalSettings `
        -RuntimeRoot $RuntimeRoot `
        -SkipVersionCheck | Out-Null
    $settings = [System.IO.File]::ReadAllText($ClaudeSettings) | ConvertFrom-Json
    Assert-True (@($settings.hooks.SessionStart).Count -eq 1) "SessionStart hook was duplicated"
    Assert-True (@($settings.hooks.SessionEnd).Count -eq 1) "SessionEnd hook was duplicated"
    Assert-True ($settings.statusLine.command -match "token-mass-windows\.ps1") "statusLine bridge missing"
    Assert-True (Test-Path -LiteralPath (Join-Path $RuntimeRoot "profile.json")) "Terminal fragment missing"
    Assert-True (-not (Test-Path -LiteralPath $LegacyState)) "legacy install state was not migrated"
    $legacyConfigAfter = [System.IO.File]::ReadAllText($LegacyGhosttyConfig)
    Assert-True ($legacyConfigAfter -match "font-size = 13") "unrelated Ghostty config was lost"
    Assert-True ($legacyConfigAfter -notmatch "ghostty-supernova") "legacy Ghostty block remains"

    $bridge = Join-Path $RuntimeRoot "token-mass-windows.ps1"
    $generated = Join-Path $RuntimeRoot "supernova-windows.generated.hlsl"
    $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $TerminalSettings
    $before = (Get-Item -LiteralPath $TerminalSettings).LastWriteTimeUtc
    Start-Sleep -Milliseconds 20
    $output = '{"context_window":{"used_percentage":95,"total_input_tokens":190000,"context_window_size":200000},"model":{"display_name":"Opus"}}' |
        & $bridge
    Assert-True (($output -join "") -match "95% - QUASAR - Opus") "status line output is wrong"
    $shader = [System.IO.File]::ReadAllText($generated)
    Assert-True ($shader.StartsWith("#define TOKEN_LEVEL 0.95")) "level define is wrong"
    Assert-True ($shader -match "#define TOKEN_MASS_K 190") "mass define is wrong"
    Assert-True ((Get-Item -LiteralPath $TerminalSettings).LastWriteTimeUtc -gt $before) "Terminal reload was not triggered"

    '{"hook_event_name":"SessionEnd"}' | & $bridge
    $shader = [System.IO.File]::ReadAllText($generated)
    Assert-True ($shader -match "#define TOKEN_ACTIVE 0") "SessionEnd did not disable the shader"

    & (Join-Path $Root "uninstall.ps1") -ClaudeSettings $ClaudeSettings | Out-Null
    $settings = [System.IO.File]::ReadAllText($ClaudeSettings) | ConvertFrom-Json
    Assert-True ($null -ne $settings.permissions) "existing Claude settings were lost"
    Assert-True ($null -ne $settings.hooks.PSObject.Properties["PreToolUse"]) "existing hooks were lost"
    Assert-True ($settings.statusLine.command -eq "bash ~/.claude/statusline-command.sh") "pre-legacy statusLine was not restored"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot "profile.json"))) "fragment was not removed"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $ClaudeSettings) "ghostty-supernova.windows.install.json"))) "install state was not removed"

    Write-Output "Windows bridge/install/uninstall integration tests passed."
}
finally {
    Remove-Item Env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $TemporaryRoot) {
        Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force
    }
}
