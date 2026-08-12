$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TemporaryRoot = Join-Path $env:TEMP ("ghostty-supernova-test-" + [guid]::NewGuid().ToString("N"))
$ClaudeSettings = Join-Path $TemporaryRoot ".claude\settings.json"
$TerminalSettings = Join-Path $TemporaryRoot "terminal\settings.json"
$RuntimeRoot = Join-Path $TemporaryRoot "runtime"
$LegacyState = Join-Path $TemporaryRoot ".claude\ghostty-supernova.install.json"
$LegacyGhosttyConfig = Join-Path $TemporaryRoot "ghostty\config.ghostty"
$ScopedProject = Join-Path $TemporaryRoot "ScopedProject"
$OtherProject = Join-Path $TemporaryRoot "OtherProject"
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
    [System.IO.Directory]::CreateDirectory($ScopedProject) | Out-Null
    [System.IO.Directory]::CreateDirectory($OtherProject) | Out-Null
    $env:GHOSTTY_SUPERNOVA_DISABLE_OVERLAY = "1"
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

    foreach ($file in @("install.ps1", "uninstall.ps1", "preview.ps1", "token-test.ps1", "token-mass-windows.ps1", "token-star-overlay.ps1")) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $Root $file), [ref]$tokens, [ref]$parseErrors
        ) | Out-Null
        Assert-True ($parseErrors.Count -eq 0) "$file has PowerShell syntax errors"
    }

    $overlayTest = & powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass `
        -File (Join-Path $Root "token-star-overlay.ps1") -SelfTest -Demo
    Assert-True ($LASTEXITCODE -eq 0) "IDE overlay self-test failed"
    Assert-True (($overlayTest -join "") -match "self-test OK") "IDE overlay self-test output is wrong"

    $previewPort = 42000 + (Get-Random -Minimum 0 -Maximum 1000)
    $previewTest = & (Join-Path $Root "preview.ps1") -Port $previewPort -Test
    Assert-True (($previewTest -join "") -match "lifecycle test OK") "local preview lifecycle test failed"
    Assert-True (-not (Get-NetTCPConnection -LocalPort $previewPort -State Listen -ErrorAction SilentlyContinue)) "preview server was left running"

    & (Join-Path $Root "install.ps1") `
        -ClaudeSettings $ClaudeSettings `
        -TerminalSettings $TerminalSettings `
        -RuntimeRoot $RuntimeRoot `
        -ProjectPath $ScopedProject `
        -SkipVersionCheck `
        -NoLaunch | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "installer returned a failure"

    # Reinstall must not duplicate hooks or overwrite the original backup.
    & (Join-Path $Root "install.ps1") `
        -ClaudeSettings $ClaudeSettings `
        -TerminalSettings $TerminalSettings `
        -RuntimeRoot $RuntimeRoot `
        -ProjectPath $ScopedProject `
        -SkipVersionCheck `
        -NoLaunch | Out-Null
    $settings = [System.IO.File]::ReadAllText($ClaudeSettings) | ConvertFrom-Json
    Assert-True (@($settings.hooks.SessionStart).Count -eq 1) "SessionStart hook was duplicated"
    Assert-True (@($settings.hooks.SessionEnd).Count -eq 1) "SessionEnd hook was duplicated"
    Assert-True ($settings.statusLine.command -match "token-mass-windows\.ps1") "statusLine bridge missing"
    Assert-True ([int]$settings.statusLine.refreshInterval -eq 5) "statusLine refresh interval is unsafe for the PowerShell bridge"
    Assert-True (Test-Path -LiteralPath (Join-Path $RuntimeRoot "profile.json")) "Terminal fragment missing"
    Assert-True (Test-Path -LiteralPath (Join-Path $RuntimeRoot "token-star-overlay.ps1")) "IDE overlay missing"
    Assert-True (Test-Path -LiteralPath (Join-Path $RuntimeRoot "overlay.enabled")) "overlay enable marker missing"
    $projectScope = [System.IO.File]::ReadAllText((Join-Path $RuntimeRoot "project-scope.json")) | ConvertFrom-Json
    Assert-True ($projectScope.root -eq $ScopedProject) "project scope root is wrong"
    Assert-True ($projectScope.name -eq "ScopedProject") "project scope name is wrong"
    $terminalProfile = [System.IO.File]::ReadAllText((Join-Path $RuntimeRoot "profile.json")) | ConvertFrom-Json
    Assert-True ($terminalProfile.profiles[0].commandline -match "claude") "Terminal profile does not auto-start Claude"
    Assert-True (-not (Test-Path -LiteralPath $LegacyState)) "legacy install state was not migrated"
    $legacyConfigAfter = [System.IO.File]::ReadAllText($LegacyGhosttyConfig)
    Assert-True ($legacyConfigAfter -match "font-size = 13") "unrelated Ghostty config was lost"
    Assert-True ($legacyConfigAfter -notmatch "ghostty-supernova") "legacy Ghostty block remains"

    function global:claude { $global:TokenStarUnexpectedClaudeLaunch = $true }
    $global:TokenStarUnexpectedClaudeLaunch = $false
    & (Join-Path $Root "install.ps1") `
        -ClaudeSettings $ClaudeSettings `
        -TerminalSettings $TerminalSettings `
        -RuntimeRoot $RuntimeRoot `
        -ProjectPath $ScopedProject `
        -SkipVersionCheck | Out-Null
    Assert-True (-not $global:TokenStarUnexpectedClaudeLaunch) "installer started a second Claude session"
    Remove-Item Function:\global:claude -ErrorAction SilentlyContinue
    Remove-Variable TokenStarUnexpectedClaudeLaunch -Scope Global -ErrorAction SilentlyContinue

    $bridge = Join-Path $RuntimeRoot "token-mass-windows.ps1"
    $generated = Join-Path $RuntimeRoot "supernova-windows.generated.hlsl"
    $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $TerminalSettings
    $before = (Get-Item -LiteralPath $TerminalSettings).LastWriteTimeUtc
    Start-Sleep -Milliseconds 20
    $fiveHourReset = [DateTimeOffset]::UtcNow.AddHours(2).AddMinutes(23).ToUnixTimeSeconds()
    $statusPayload = [ordered]@{
        workspace = [ordered]@{ project_dir = $ScopedProject; current_dir = $ScopedProject }
        context_window = [ordered]@{
            used_percentage = 95
            total_input_tokens = 190000
            total_output_tokens = 3210
            context_window_size = 200000
            current_usage = [ordered]@{
                input_tokens = 85000
                cache_creation_input_tokens = 60000
                cache_read_input_tokens = 45000
                output_tokens = 3210
            }
            breakdown = [ordered]@{
                system_prompt_tokens = 17000
                system_tools_tokens = 12000
                memory_files_tokens = 4300
                skills_tokens = 2800
            }
        }
        rate_limits = [ordered]@{
            five_hour = [ordered]@{ used_percentage = 61; resets_at = $fiveHourReset }
            seven_day = [ordered]@{ used_percentage = 28; resets_at = 0 }
        }
        model = [ordered]@{ display_name = "Opus" }
    }
    $output = ($statusPayload | ConvertTo-Json -Depth 10 -Compress) | & $bridge
    Assert-True (($output -join "") -match "95% - QUASAR - Opus") "status line output is wrong"
    $shader = [System.IO.File]::ReadAllText($generated)
    Assert-True ($shader.StartsWith("#define TOKEN_LEVEL 0.95")) "level define is wrong"
    Assert-True ($shader -match "#define TOKEN_MASS_K 190") "mass define is wrong"
    Assert-True ((Get-Item -LiteralPath $TerminalSettings).LastWriteTimeUtc -gt $before) "Terminal reload was not triggered"
    $overlayStatePath = Join-Path $RuntimeRoot "token-state.json"
    Assert-True (Test-Path -LiteralPath $overlayStatePath) "overlay state was not written"
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True ([Math]::Abs([double]$overlayState.level - 0.95) -lt 0.000001) "overlay level is wrong"
    Assert-True ([long]$overlayState.tokens -eq 190000) "overlay token mass is wrong"
    Assert-True ([bool]$overlayState.active) "overlay was not activated"
    Assert-True ($overlayState.stage -eq "QUASAR") "overlay stage is wrong"
    Assert-True ($overlayState.project_root -eq $ScopedProject) "overlay project root is wrong"
    Assert-True ($overlayState.project_name -eq "ScopedProject") "overlay project name is wrong"
    Assert-True ([long]$overlayState.breakdown.fresh_input_tokens -eq 85000) "fresh input breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.cache_creation_input_tokens -eq 60000) "cache creation breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.cache_read_input_tokens -eq 45000) "cache read breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.total_output_tokens -eq 3210) "output token breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.system_prompt_tokens -eq 17000) "system prompt breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.system_tools_tokens -eq 12000) "system tools breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.memory_files_tokens -eq 4300) "memory files breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.skills_tokens -eq 2800) "skills breakdown is wrong"
    Assert-True ([double]$overlayState.rate_limits.five_hour.used_percentage -eq 61) "five-hour percentage is wrong"
    Assert-True ([long]$overlayState.rate_limits.five_hour.resets_at -eq $fiveHourReset) "five-hour reset is wrong"

    [void]$statusPayload.context_window.Remove("breakdown")
    $null = ($statusPayload | ConvertTo-Json -Depth 10 -Compress) | & $bridge
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True ([long]$overlayState.breakdown.system_prompt_tokens -eq -1) "missing system prompt tokens should stay unavailable"
    Assert-True ([long]$overlayState.breakdown.system_tools_tokens -eq -1) "missing system tools tokens should stay unavailable"
    Assert-True ([long]$overlayState.breakdown.memory_files_tokens -eq -1) "missing memory file tokens should stay unavailable"
    Assert-True ([long]$overlayState.breakdown.skills_tokens -eq -1) "missing skill tokens should stay unavailable"

    $outsidePayload = [ordered]@{
        workspace = [ordered]@{ project_dir = $OtherProject; current_dir = $OtherProject }
        context_window = [ordered]@{ used_percentage = 50; total_input_tokens = 100000; context_window_size = 200000 }
    }
    $outsideOutput = ($outsidePayload | ConvertTo-Json -Depth 10 -Compress) | & $bridge
    Assert-True ([string]::IsNullOrWhiteSpace(($outsideOutput -join ""))) "status line leaked into another project"
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True (-not [bool]$overlayState.active) "overlay remained active in another project"

    ([ordered]@{ hook_event_name = "SessionEnd"; workspace = [ordered]@{ project_dir = $ScopedProject } } | ConvertTo-Json -Compress) | & $bridge
    $shader = [System.IO.File]::ReadAllText($generated)
    Assert-True ($shader -match "#define TOKEN_ACTIVE 0") "SessionEnd did not disable the shader"
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True (-not [bool]$overlayState.active) "SessionEnd did not disable the overlay"
    $overlayPositionPath = Join-Path $RuntimeRoot "overlay-position.json"
    [System.IO.File]::WriteAllText($overlayPositionPath, '{"x":0.5,"y":0.5}', $Utf8NoBom)

    # Running install from inside the hidden clone must scope its parent project.
    $installProject = Join-Path $TemporaryRoot "InstallFromProject"
    $hiddenClone = Join-Path $installProject ".claude-token-star"
    [System.IO.Directory]::CreateDirectory($hiddenClone) | Out-Null
    Push-Location -LiteralPath $hiddenClone
    try {
        & (Join-Path $Root "install.ps1") `
            -ClaudeSettings $ClaudeSettings `
            -TerminalSettings $TerminalSettings `
            -RuntimeRoot $RuntimeRoot `
            -SkipVersionCheck `
            -NoLaunch | Out-Null
    }
    finally { Pop-Location }
    $projectScope = [System.IO.File]::ReadAllText((Join-Path $RuntimeRoot "project-scope.json")) | ConvertFrom-Json
    Assert-True ($projectScope.root -eq $installProject) "hidden clone was incorrectly used as the project scope"

    & (Join-Path $Root "uninstall.ps1") -ClaudeSettings $ClaudeSettings | Out-Null
    $settings = [System.IO.File]::ReadAllText($ClaudeSettings) | ConvertFrom-Json
    Assert-True ($null -ne $settings.permissions) "existing Claude settings were lost"
    Assert-True ($null -ne $settings.hooks.PSObject.Properties["PreToolUse"]) "existing hooks were lost"
    Assert-True ($settings.statusLine.command -eq "bash ~/.claude/statusline-command.sh") "pre-legacy statusLine was not restored"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot "profile.json"))) "fragment was not removed"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot "token-star-overlay.ps1"))) "overlay was not removed"
    Assert-True (-not (Test-Path -LiteralPath $overlayStatePath)) "overlay state was not removed"
    Assert-True (-not (Test-Path -LiteralPath $overlayPositionPath)) "saved overlay position was not removed"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot "project-scope.json"))) "project scope was not removed"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot "overlay.enabled"))) "overlay marker was not removed"
    Assert-True (-not (Test-Path -LiteralPath $RuntimeRoot)) "runtime directory was not removed completely"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $ClaudeSettings) "ghostty-supernova.windows.install.json"))) "install state was not removed"

    Write-Output "Windows bridge/install/uninstall integration tests passed."
}
finally {
    Remove-Item Function:\global:claude -ErrorAction SilentlyContinue
    Remove-Variable TokenStarUnexpectedClaudeLaunch -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS -ErrorAction SilentlyContinue
    Remove-Item Env:GHOSTTY_SUPERNOVA_DISABLE_OVERLAY -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $TemporaryRoot) {
        Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force
    }
}
