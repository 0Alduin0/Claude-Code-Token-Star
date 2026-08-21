$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WindowsSource = Join-Path $Root "src\windows"
$ToolsRoot = Join-Path $Root "tools"
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

function Get-CanonicalDirectoryPath {
    param([string]$Path)
    return (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-SameDirectoryPath {
    param([string]$Actual, [string]$Expected)
    $actualPath = Get-CanonicalDirectoryPath $Actual
    $expectedPath = Get-CanonicalDirectoryPath $Expected
    return $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)
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

    foreach ($file in @(
        (Join-Path $WindowsSource "install.ps1"),
        (Join-Path $WindowsSource "uninstall.ps1"),
        (Join-Path $ToolsRoot "preview.ps1"),
        (Join-Path $ToolsRoot "token-test.ps1"),
        (Join-Path $WindowsSource "token-mass-windows.ps1"),
        (Join-Path $WindowsSource "token-star-overlay.ps1")
    )) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $file, [ref]$tokens, [ref]$parseErrors
        ) | Out-Null
        Assert-True ($parseErrors.Count -eq 0) "$file has PowerShell syntax errors"
    }

    $overlaySelfTestPosition = Join-Path $TemporaryRoot "overlay-self-test-position.json"
    [System.IO.File]::WriteAllText(
        $overlaySelfTestPosition,
        '{"x":0.5,"y":0.5,"scale":2,"locked":true,"stage_mode":"QUASAR","grow_with_tokens":true}',
        $Utf8NoBom
    )
    $overlayTest = & powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass `
        -File (Join-Path $WindowsSource "token-star-overlay.ps1") -SelfTest -Demo `
        -PositionPath $overlaySelfTestPosition
    Assert-True ($LASTEXITCODE -eq 0) "IDE overlay self-test failed"
    Assert-True (($overlayTest -join "") -match "self-test OK") "IDE overlay self-test output is wrong"

    $previewPort = 42000 + (Get-Random -Minimum 0 -Maximum 1000)
    $previewTest = & (Join-Path $ToolsRoot "preview.ps1") -Port $previewPort -Test
    Assert-True (($previewTest -join "") -match "lifecycle test OK") "local preview lifecycle test failed"
    Assert-True (-not (Get-NetTCPConnection -LocalPort $previewPort -State Listen -ErrorAction SilentlyContinue)) "preview server was left running"

    & (Join-Path $WindowsSource "install.ps1") `
        -ClaudeSettings $ClaudeSettings `
        -TerminalSettings $TerminalSettings `
        -RuntimeRoot $RuntimeRoot `
        -ProjectPath $ScopedProject `
        -SkipVersionCheck `
        -NoLaunch | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "installer returned a failure"

    # Reinstall must not duplicate hooks or overwrite the original backup.
    & (Join-Path $WindowsSource "install.ps1") `
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
    Assert-True (Test-SameDirectoryPath ([string]$projectScope.root) $ScopedProject) `
        "project scope root is wrong (expected '$ScopedProject', got '$($projectScope.root)')"
    Assert-True ($projectScope.name -eq "ScopedProject") "project scope name is wrong"
    $terminalProfile = [System.IO.File]::ReadAllText((Join-Path $RuntimeRoot "profile.json")) | ConvertFrom-Json
    Assert-True ($terminalProfile.profiles[0].commandline -match "claude") "Terminal profile does not auto-start Claude"
    Assert-True (-not (Test-Path -LiteralPath $LegacyState)) "legacy install state was not migrated"
    $legacyConfigAfter = [System.IO.File]::ReadAllText($LegacyGhosttyConfig)
    Assert-True ($legacyConfigAfter -match "font-size = 13") "unrelated Ghostty config was lost"
    Assert-True ($legacyConfigAfter -notmatch "ghostty-supernova") "legacy Ghostty block remains"

    function global:claude { $global:TokenStarUnexpectedClaudeLaunch = $true }
    $global:TokenStarUnexpectedClaudeLaunch = $false
    & (Join-Path $WindowsSource "install.ps1") `
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
    & $bridge -Off | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot "overlay.enabled"))) `
        "off command did not persistently disable the overlay"
    & $bridge -On | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $RuntimeRoot "overlay.enabled")) `
        "on command did not re-enable the overlay"
    $env:GHOSTTY_SUPERNOVA_TERMINAL_SETTINGS = $TerminalSettings
    $before = (Get-Item -LiteralPath $TerminalSettings).LastWriteTimeUtc
    Start-Sleep -Milliseconds 20
    $fiveHourReset = [DateTimeOffset]::UtcNow.AddHours(2).AddMinutes(23).ToUnixTimeSeconds()
    $statusPayload = [ordered]@{
        session_id = "session-high"
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
        }
        rate_limits = [ordered]@{
            five_hour = [ordered]@{ used_percentage = 61; resets_at = $fiveHourReset }
            seven_day = [ordered]@{ used_percentage = 28; resets_at = 0 }
        }
        model = [ordered]@{ display_name = "Opus" }
        effort = [ordered]@{ level = "high" }
    }
    $output = ($statusPayload | ConvertTo-Json -Depth 10 -Compress) | & $bridge
    Assert-True (($output -join "") -match "MASS 190\.0K / 200\.0K TOKENS - 95% - QUASAR - Opus - HIGH effort") "status line output is wrong"
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
    Assert-True (Test-SameDirectoryPath ([string]$overlayState.project_root) $ScopedProject) "overlay project root is wrong"
    Assert-True ($overlayState.project_name -eq "ScopedProject") "overlay project name is wrong"
    Assert-True ($overlayState.model -eq "Opus") "overlay model is wrong"
    Assert-True ($overlayState.effort -eq "high") "overlay effort is wrong"
    Assert-True ([long]$overlayState.breakdown.fresh_input_tokens -eq 85000) "fresh input breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.cache_creation_input_tokens -eq 60000) "cache creation breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.cache_read_input_tokens -eq 45000) "cache read breakdown is wrong"
    Assert-True ([long]$overlayState.breakdown.total_output_tokens -eq 3210) "output token breakdown is wrong"
    Assert-True ([double]$overlayState.rate_limits.five_hour.used_percentage -eq 61) "five-hour percentage is wrong"
    Assert-True ([long]$overlayState.rate_limits.five_hour.resets_at -eq $fiveHourReset) "five-hour reset is wrong"

    $lowerSessionPayload = [ordered]@{
        session_id = "session-low"
        workspace = [ordered]@{ project_dir = $ScopedProject; current_dir = $ScopedProject }
        context_window = [ordered]@{ used_percentage = 40; total_input_tokens = 80000; context_window_size = 200000 }
        model = [ordered]@{ display_name = "Sonnet" }
        effort = [ordered]@{ level = "medium" }
    }
    ($lowerSessionPayload | ConvertTo-Json -Depth 10 -Compress) | & $bridge | Out-Null
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True ([long]$overlayState.tokens -eq 190000) "lower-token tab replaced the highest-token tab"
    Assert-True ([int]$overlayState.active_sessions -eq 2) "active Claude tab count is wrong"

    $lowerSessionPayload.context_window.used_percentage = 98
    $lowerSessionPayload.context_window.total_input_tokens = 196000
    ($lowerSessionPayload | ConvertTo-Json -Depth 10 -Compress) | & $bridge | Out-Null
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True ([long]$overlayState.tokens -eq 196000) "highest-token tab was not selected"
    Assert-True ($overlayState.model -eq "Sonnet") "selected tab metadata is wrong"

    ([ordered]@{ hook_event_name = "SessionEnd"; session_id = "session-low"; workspace = [ordered]@{ project_dir = $ScopedProject } } | ConvertTo-Json -Compress) | & $bridge
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True ([long]$overlayState.tokens -eq 190000) "closing the highest-token tab did not restore the next-highest tab"
    Assert-True ([int]$overlayState.active_sessions -eq 1) "closed Claude tab remained active"

    $outsidePayload = [ordered]@{
        workspace = [ordered]@{ project_dir = $OtherProject; current_dir = $OtherProject }
        context_window = [ordered]@{ used_percentage = 50; total_input_tokens = 100000; context_window_size = 200000 }
    }
    $outsideOutput = ($outsidePayload | ConvertTo-Json -Depth 10 -Compress) | & $bridge
    Assert-True ([string]::IsNullOrWhiteSpace(($outsideOutput -join ""))) "status line leaked into another project"
    $overlayState = [System.IO.File]::ReadAllText($overlayStatePath) | ConvertFrom-Json
    Assert-True (-not [bool]$overlayState.active) "overlay remained active in another project"

    ([ordered]@{ hook_event_name = "SessionEnd"; session_id = "session-high"; workspace = [ordered]@{ project_dir = $ScopedProject } } | ConvertTo-Json -Compress) | & $bridge
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
    [System.IO.File]::WriteAllText((Join-Path $hiddenClone "VERSION"), "test`n", $Utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $hiddenClone "install.ps1"), "# test`n", $Utf8NoBom)
    Push-Location -LiteralPath $hiddenClone
    try {
        & (Join-Path $WindowsSource "install.ps1") `
            -ClaudeSettings $ClaudeSettings `
            -TerminalSettings $TerminalSettings `
            -RuntimeRoot $RuntimeRoot `
            -SkipVersionCheck `
            -NoLaunch | Out-Null
    }
    finally { Pop-Location }
    $projectScope = [System.IO.File]::ReadAllText((Join-Path $RuntimeRoot "project-scope.json")) | ConvertFrom-Json
    Assert-True (Test-SameDirectoryPath ([string]$projectScope.root) $installProject) "hidden clone was incorrectly used as the project scope"

    # The CLI passes ProjectPath explicitly, so that path must be normalized too.
    & (Join-Path $WindowsSource "install.ps1") `
        -ClaudeSettings $ClaudeSettings `
        -TerminalSettings $TerminalSettings `
        -RuntimeRoot $RuntimeRoot `
        -ProjectPath $hiddenClone `
        -SkipVersionCheck `
        -NoLaunch | Out-Null
    $projectScope = [System.IO.File]::ReadAllText((Join-Path $RuntimeRoot "project-scope.json")) | ConvertFrom-Json
    Assert-True (Test-SameDirectoryPath ([string]$projectScope.root) $installProject) `
        "explicit hidden-clone ProjectPath was incorrectly used as the project scope"

    & (Join-Path $WindowsSource "uninstall.ps1") -ClaudeSettings $ClaudeSettings | Out-Null
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

    # Default Windows installs must isolate settings, runtime state, profiles,
    # and uninstall behavior for every project.
    $oldLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = Join-Path $TemporaryRoot "local-app-data"
    try {
        & (Join-Path $WindowsSource "install.ps1") `
            -ProjectPath $ScopedProject `
            -TerminalSettings $TerminalSettings `
            -SkipVersionCheck `
            -NoLaunch | Out-Null
        & (Join-Path $WindowsSource "install.ps1") `
            -ProjectPath $OtherProject `
            -TerminalSettings $TerminalSettings `
            -SkipVersionCheck `
            -NoLaunch | Out-Null

        $settingsAPath = Join-Path $ScopedProject ".claude\settings.local.json"
        $settingsBPath = Join-Path $OtherProject ".claude\settings.local.json"
        $stateAPath = Join-Path $ScopedProject ".claude\ghostty-supernova.windows.install.json"
        $stateBPath = Join-Path $OtherProject ".claude\ghostty-supernova.windows.install.json"
        $stateA = [System.IO.File]::ReadAllText($stateAPath) | ConvertFrom-Json
        $stateB = [System.IO.File]::ReadAllText($stateBPath) | ConvertFrom-Json
        $settingsA = [System.IO.File]::ReadAllText($settingsAPath) | ConvertFrom-Json
        $settingsB = [System.IO.File]::ReadAllText($settingsBPath) | ConvertFrom-Json
        Assert-True (-not ([string]$stateA.runtime_root).Equals(
            [string]$stateB.runtime_root, [StringComparison]::OrdinalIgnoreCase
        )) "two projects shared a Windows runtime"
        Assert-True (Test-Path -LiteralPath ([string]$stateA.runtime_root)) "project A runtime is missing"
        Assert-True (Test-Path -LiteralPath ([string]$stateB.runtime_root)) "project B runtime is missing"
        Assert-True ($settingsA.statusLine.command -match [regex]::Escape([string]$stateA.runtime_root)) `
            "project A settings do not use project A runtime"
        Assert-True ($settingsB.statusLine.command -match [regex]::Escape([string]$stateB.runtime_root)) `
            "project B settings do not use project B runtime"
        $profileA = [System.IO.File]::ReadAllText((Join-Path ([string]$stateA.runtime_root) "profile.json")) | ConvertFrom-Json
        $profileB = [System.IO.File]::ReadAllText((Join-Path ([string]$stateB.runtime_root) "profile.json")) | ConvertFrom-Json
        Assert-True ($profileA.profiles[0].guid -ne $profileB.profiles[0].guid) `
            "two projects shared a Windows Terminal profile GUID"

        & (Join-Path $WindowsSource "uninstall.ps1") -ProjectPath $ScopedProject | Out-Null
        Assert-True (-not (Test-Path -LiteralPath ([string]$stateA.runtime_root))) `
            "uninstall left project A runtime behind"
        Assert-True (Test-Path -LiteralPath ([string]$stateB.runtime_root)) `
            "uninstalling project A removed project B runtime"
        $settingsBAfter = [System.IO.File]::ReadAllText($settingsBPath) | ConvertFrom-Json
        Assert-True ($settingsBAfter.statusLine.command -eq $settingsB.statusLine.command) `
            "uninstalling project A changed project B settings"

        & (Join-Path $WindowsSource "uninstall.ps1") -ProjectPath $OtherProject | Out-Null
        Assert-True (-not (Test-Path -LiteralPath ([string]$stateB.runtime_root))) `
            "uninstall left project B runtime behind"
    }
    finally { $env:LOCALAPPDATA = $oldLocalAppData }

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
