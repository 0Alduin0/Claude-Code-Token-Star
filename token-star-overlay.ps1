[CmdletBinding()]
param(
    [string]$StatePath,
    [string]$PositionPath,
    [string]$PidPath,
    [string]$StopPath,
    [switch]$SelfTest,
    [switch]$Demo,
    [double]$DemoLevel = -1.0
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $ScriptRoot "token-state.json"
}
if ([string]::IsNullOrWhiteSpace($PositionPath)) {
    $PositionPath = Join-Path $ScriptRoot "overlay-position.json"
}
if ([string]::IsNullOrWhiteSpace($PidPath)) {
    $PidPath = Join-Path $ScriptRoot "token-star-overlay.pid.json"
}
if ([string]::IsNullOrWhiteSpace($StopPath)) {
    $StopPath = Join-Path $ScriptRoot "token-star-overlay.stop"
}
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$CreatedNew = $false
$OverlayMutex = New-Object System.Threading.Mutex($true, "Local\ClaudeCodeTokenStarOverlay", [ref]$CreatedNew)
if (-not $CreatedNew -and -not $SelfTest) {
    $OverlayMutex.Dispose()
    exit 0
}
if (-not $SelfTest) {
    $process = Get-Process -Id $PID
    $pidRecord = [ordered]@{
        schema = 1
        pid = $PID
        started_utc = $process.StartTime.ToUniversalTime().ToString("o")
    }
    [IO.File]::WriteAllText($PidPath + ".tmp", ($pidRecord | ConvertTo-Json -Compress) + "`n", $Utf8NoBom)
    Move-Item -LiteralPath ($PidPath + ".tmp") -Destination $PidPath -Force
    Remove-Item -LiteralPath $StopPath -Force -ErrorAction SilentlyContinue
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TokenStarNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int maxCount);
    [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll", SetLastError=true)] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
}
"@

[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="500" Height="500" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ShowActivated="False" Focusable="False" ResizeMode="NoResize">
  <Canvas Name="Root" Width="500" Height="500">
    <Canvas Name="Stars" />
    <Ellipse Name="Nebula" Opacity="0">
    </Ellipse>
    <Ellipse Name="PulseRingOuter" StrokeThickness="3" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="3" /></Ellipse.Effect>
    </Ellipse>
    <Ellipse Name="PulseRingInner" StrokeThickness="2" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="1" /></Ellipse.Effect>
    </Ellipse>
    <Canvas Name="Rays" />
    <Canvas Name="Particles" />

    <Ellipse Name="HaloOuter" Stroke="#66FFB52E" StrokeThickness="3" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="3" /></Ellipse.Effect>
    </Ellipse>
    <Ellipse Name="HaloInner" Stroke="#AAFFE47A" StrokeThickness="4" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="2" /></Ellipse.Effect>
    </Ellipse>

    <Rectangle Name="JetAura" Width="94" Height="360" RadiusX="40" RadiusY="40" Opacity="0"
               Fill="#553968FF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.RenderTransform><RotateTransform Angle="-12" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="JetGlow" Width="46" Height="350" RadiusX="18" RadiusY="18" Opacity="0"
               RenderTransformOrigin="0.5,0.5">
      <Rectangle.Fill>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#003D73FF" Offset="0" />
          <GradientStop Color="#DD4F7FFF" Offset="0.28" />
          <GradientStop Color="#FFFFFFFF" Offset="0.5" />
          <GradientStop Color="#DD4F7FFF" Offset="0.72" />
          <GradientStop Color="#003D73FF" Offset="1" />
        </LinearGradientBrush>
      </Rectangle.Fill>
      <Rectangle.Effect><BlurEffect Radius="7" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="-12" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="JetCore" Width="10" Height="342" RadiusX="5" RadiusY="5" Opacity="0"
               Fill="#EFFFFFFF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="2" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="-12" /></Rectangle.RenderTransform>
    </Rectangle>

    <Rectangle Name="NeutronBeamGlow" Width="360" Height="28" RadiusX="12" RadiusY="12" Opacity="0"
               Fill="#884AA8FF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="6" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="NeutronBeam" Width="350" Height="6" RadiusX="3" RadiusY="3" Opacity="0"
               Fill="#EEEAFFFF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="1" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>

    <Ellipse Name="Glow" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="12" /></Ellipse.Effect>
    </Ellipse>
    <Ellipse Name="Core" Opacity="0" />
    <Canvas Name="Surface" />

    <Ellipse Name="DiskAura" Width="330" Height="88" Stroke="#77FF4724" StrokeThickness="28"
             Opacity="0" RenderTransformOrigin="0.5,0.5">
      <Ellipse.RenderTransform><RotateTransform Angle="-12" /></Ellipse.RenderTransform>
    </Ellipse>
    <Ellipse Name="DiskOuter" Width="302" Height="72" Stroke="#CCFF8D2F" StrokeThickness="4"
             StrokeDashArray="1 3 7 2" Opacity="0" RenderTransformOrigin="0.5,0.5">
      <Ellipse.RenderTransform><RotateTransform Angle="-12" /></Ellipse.RenderTransform>
    </Ellipse>
    <Ellipse Name="DiskGlow" Width="270" Height="62" Stroke="#BBFF6B26" StrokeThickness="18"
             StrokeDashArray="3 1 1 1" Opacity="0" RenderTransformOrigin="0.5,0.5">
      <Ellipse.Effect><BlurEffect Radius="6" /></Ellipse.Effect>
      <Ellipse.RenderTransform><RotateTransform Angle="-12" /></Ellipse.RenderTransform>
    </Ellipse>
    <Ellipse Name="Disk" Width="250" Height="46" StrokeThickness="8" StrokeDashArray="5 1 2 1"
             Opacity="0" RenderTransformOrigin="0.5,0.5">
      <Ellipse.Stroke>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#FFFF2A14" Offset="0" />
          <GradientStop Color="#FFFF69E8" Offset="0.24" />
          <GradientStop Color="#FFFFFFFF" Offset="0.66" />
          <GradientStop Color="#FFFFAF35" Offset="1" />
        </LinearGradientBrush>
      </Ellipse.Stroke>
      <Ellipse.Effect><BlurEffect Radius="1" /></Ellipse.Effect>
      <Ellipse.RenderTransform><RotateTransform Angle="-12" /></Ellipse.RenderTransform>
    </Ellipse>
    <Ellipse Name="DiskHot" Width="220" Height="34" Stroke="#EEFFFFFF" StrokeThickness="3"
             StrokeDashArray="8 2 1 2" Opacity="0" RenderTransformOrigin="0.5,0.5">
      <Ellipse.RenderTransform><RotateTransform Angle="-12" /></Ellipse.RenderTransform>
    </Ellipse>
    <Ellipse Name="BlackCore" Width="92" Height="92" Fill="#FF010205" Stroke="#FFFFC85A"
             StrokeThickness="5" Opacity="0">
    </Ellipse>
    <Path Name="DiskFrontGlow" Data="M 420,165 A 110,17 0 0 1 200,165"
          Stroke="#CCFF5B2B" StrokeThickness="17" StrokeDashArray="5 1 2 1"
          StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0">
      <Path.Effect><BlurEffect Radius="5" /></Path.Effect>
      <Path.RenderTransform><RotateTransform Angle="-12" CenterX="310" CenterY="165" /></Path.RenderTransform>
    </Path>
    <Path Name="DiskFront" Data="M 420,165 A 110,17 0 0 1 200,165"
          StrokeThickness="8" StrokeDashArray="5 1 2 1"
          StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0">
      <Path.Stroke>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#FFFF2A14" Offset="0" />
          <GradientStop Color="#FFFF69E8" Offset="0.24" />
          <GradientStop Color="#FFFFFFFF" Offset="0.66" />
          <GradientStop Color="#FFFFAF35" Offset="1" />
        </LinearGradientBrush>
      </Path.Stroke>
      <Path.RenderTransform><RotateTransform Angle="-12" CenterX="310" CenterY="165" /></Path.RenderTransform>
    </Path>

    <Ellipse Name="DragHandle" Width="92" Height="92" Fill="#01000000"
             Cursor="SizeAll" ToolTip="Drag the token star" />

    <Border Name="MassPanel" Background="#F203060C" BorderBrush="#CC5F91BF"
            BorderThickness="1" CornerRadius="4" Padding="8,4" Opacity="0">
      <StackPanel Orientation="Horizontal">
        <TextBlock Name="MassText" Text="MASS 0" Foreground="#FFF8FCFF"
                   FontFamily="Consolas" FontWeight="Bold" FontSize="16" VerticalAlignment="Center" />
        <TextBlock Name="RateText" Text=" | 5H -- | --" Foreground="#FFA9C4DF"
                   FontFamily="Consolas" FontSize="12" VerticalAlignment="Center" Margin="5,0,0,0" />
        <Button Name="DetailsButton" Content="&#x25BC;" ToolTip="Token details"
                Foreground="#FFB8D8F8" Background="Transparent" BorderThickness="0"
                FontSize="12" Padding="8,0,0,0" Cursor="Hand" Focusable="False" />
      </StackPanel>
    </Border>
    <Border Name="DetailsPanel" Width="250" Background="#F203060C" BorderBrush="#AA4C7199"
            BorderThickness="1" CornerRadius="4" Padding="10,8" Opacity="0"
            Visibility="Collapsed" IsHitTestVisible="False">
      <TextBlock Name="DetailsText" Foreground="#FFE8F4FF" FontFamily="Consolas"
                 FontSize="12" LineHeight="18" />
    </Border>
  </Canvas>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$Root = $Window.FindName("Root")
$Stars = $Window.FindName("Stars")
$Rays = $Window.FindName("Rays")
$Particles = $Window.FindName("Particles")
$Nebula = $Window.FindName("Nebula")
$PulseRingOuter = $Window.FindName("PulseRingOuter")
$PulseRingInner = $Window.FindName("PulseRingInner")
$HaloOuter = $Window.FindName("HaloOuter")
$HaloInner = $Window.FindName("HaloInner")
$JetAura = $Window.FindName("JetAura")
$JetGlow = $Window.FindName("JetGlow")
$JetCore = $Window.FindName("JetCore")
$NeutronBeamGlow = $Window.FindName("NeutronBeamGlow")
$NeutronBeam = $Window.FindName("NeutronBeam")
$Glow = $Window.FindName("Glow")
$Core = $Window.FindName("Core")
$Surface = $Window.FindName("Surface")
$DiskGlow = $Window.FindName("DiskGlow")
$Disk = $Window.FindName("Disk")
$DiskAura = $Window.FindName("DiskAura")
$DiskOuter = $Window.FindName("DiskOuter")
$DiskHot = $Window.FindName("DiskHot")
$BlackCore = $Window.FindName("BlackCore")
$DiskFrontGlow = $Window.FindName("DiskFrontGlow")
$DiskFront = $Window.FindName("DiskFront")
$DragHandle = $Window.FindName("DragHandle")
$MassPanel = $Window.FindName("MassPanel")
$MassText = $Window.FindName("MassText")
$RateText = $Window.FindName("RateText")
$DetailsButton = $Window.FindName("DetailsButton")
$DetailsPanel = $Window.FindName("DetailsPanel")
$DetailsText = $Window.FindName("DetailsText")

foreach ($visual in @(
    $Stars, $Nebula, $PulseRingOuter, $PulseRingInner, $Rays, $Particles,
    $HaloOuter, $HaloInner, $JetAura, $JetGlow, $JetCore,
    $NeutronBeamGlow, $NeutronBeam, $Glow, $Core, $Surface,
    $DiskAura, $DiskOuter, $DiskGlow, $Disk, $DiskHot, $BlackCore,
    $DiskFrontGlow, $DiskFront
)) {
    $visual.IsHitTestVisible = $false
}
$DragHandle.IsHitTestVisible = $true
$MassPanel.IsHitTestVisible = $true

$CenterX = 310.0
$CenterY = 165.0
$Random = New-Object System.Random 164
$StarDots = @()
for ($index = 0; $index -lt 32; $index++) {
    $dot = New-Object Windows.Shapes.Ellipse
    $size = 1.0 + $Random.NextDouble() * 2.2
    $dot.Width = $size
    $dot.Height = $size
    $dot.Fill = [Windows.Media.Brushes]::LightSkyBlue
    $dot.Opacity = 0.18 + $Random.NextDouble() * 0.48
    [Windows.Controls.Canvas]::SetLeft($dot, 18 + $Random.NextDouble() * 460)
    [Windows.Controls.Canvas]::SetTop($dot, 18 + $Random.NextDouble() * 300)
    [void]$Stars.Children.Add($dot)
    $StarDots += $dot
}

$RayLines = @()
for ($index = 0; $index -lt 18; $index++) {
    $line = New-Object Windows.Shapes.Line
    $line.StrokeThickness = if ($index % 3 -eq 0) { 2.0 } else { 1.0 }
    $line.Opacity = 0.0
    [void]$Rays.Children.Add($line)
    $RayLines += $line
}

$ParticleDots = @()
for ($index = 0; $index -lt 36; $index++) {
    $dot = New-Object Windows.Shapes.Ellipse
    $size = 1.2 + ($index % 5) * 0.55
    $dot.Width = $size
    $dot.Height = $size
    $dot.Fill = [Windows.Media.Brushes]::White
    $dot.Opacity = 0.0
    [void]$Particles.Children.Add($dot)
    $ParticleDots += $dot
}

$SurfaceDots = @()
for ($index = 0; $index -lt 10; $index++) {
    $spot = New-Object Windows.Shapes.Ellipse
    $size = 3.0 + ($index % 4) * 1.4
    $spot.Width = $size
    $spot.Height = $size
    $spot.Fill = [Windows.Media.Brushes]::White
    $spot.Opacity = 0.0
    [void]$Surface.Children.Add($spot)
    $SurfaceDots += $spot
}

function Convert-Color([string]$Value) {
    return [Windows.Media.ColorConverter]::ConvertFromString($Value)
}

function New-RadialBrush([string]$CenterColor, [string]$EdgeColor) {
    $brush = New-Object Windows.Media.RadialGradientBrush
    $brush.Center = New-Object Windows.Point(0.5, 0.5)
    $brush.GradientOrigin = New-Object Windows.Point(0.36, 0.30)
    $brush.RadiusX = 0.58
    $brush.RadiusY = 0.58
    [void]$brush.GradientStops.Add((New-Object Windows.Media.GradientStop((Convert-Color "#FFFFFFFF"), 0.0)))
    [void]$brush.GradientStops.Add((New-Object Windows.Media.GradientStop((Convert-Color $CenterColor), 0.38)))
    [void]$brush.GradientStops.Add((New-Object Windows.Media.GradientStop((Convert-Color $EdgeColor), 1.0)))
    $brush.Freeze()
    return $brush
}

$SolidBrushCache = @{}
$RadialBrushCache = @{}
function Get-SolidBrush([string]$Color) {
    if (-not $SolidBrushCache.ContainsKey($Color)) {
        $brush = New-Object Windows.Media.SolidColorBrush((Convert-Color $Color))
        $brush.Freeze()
        $SolidBrushCache[$Color] = $brush
    }
    return $SolidBrushCache[$Color]
}

function Get-RadialBrush([string]$CenterColor, [string]$EdgeColor) {
    $key = "$CenterColor|$EdgeColor"
    if (-not $RadialBrushCache.ContainsKey($key)) {
        $RadialBrushCache[$key] = New-RadialBrush $CenterColor $EdgeColor
    }
    return $RadialBrushCache[$key]
}

function Set-CenteredSize($Element, [double]$Width, [double]$Height) {
    $Element.Width = $Width
    $Element.Height = $Height
    [Windows.Controls.Canvas]::SetLeft($Element, $CenterX - $Width / 2.0)
    [Windows.Controls.Canvas]::SetTop($Element, $CenterY - $Height / 2.0)
}

function Get-Stage([double]$Level) {
    if ($Level -lt 0.15) { return "RED DWARF" }
    if ($Level -lt 0.35) { return "MAIN SEQUENCE" }
    if ($Level -lt 0.55) { return "BLUE GIANT" }
    if ($Level -lt 0.75) { return "HYPERGIANT" }
    if ($Level -lt 0.90) { return "NEUTRON STAR" }
    return "QUASAR"
}

function Format-Mass([long]$Tokens) {
    if ($Tokens -ge 1000) { return "{0:0}" -f ($Tokens / 1000.0) }
    return [string]$Tokens
}

function Format-TokenDetail([long]$Tokens) {
    return $Tokens.ToString("N0", [Globalization.CultureInfo]::CurrentCulture)
}

function Format-ResetRemaining([long]$EpochSeconds) {
    if ($EpochSeconds -le 0) { return "--" }
    $remaining = [DateTimeOffset]::FromUnixTimeSeconds($EpochSeconds) - [DateTimeOffset]::UtcNow
    if ($remaining.TotalSeconds -le 0) { return "now" }
    if ($remaining.TotalHours -ge 1.0) {
        return ("{0}h {1}m" -f [Math]::Floor($remaining.TotalHours), $remaining.Minutes)
    }
    return ("{0}m" -f [Math]::Max(1, [Math]::Ceiling($remaining.TotalMinutes)))
}

function Get-RateSummary {
    $fiveHour = $State.rate_limits.five_hour
    $used = [double]$fiveHour.used_percentage
    if ($used -lt 0.0) { return "5H -- | --" }
    return ("5H %{0} | {1}" -f [Math]::Round($used), (Format-ResetRemaining ([long]$fiveHour.resets_at)))
}

function Get-DetailsText {
    $breakdown = $State.breakdown
    $limits = $State.rate_limits
    return @(
        "CONTEXT $([Math]::Round([double]$State.level * 100))%"
        "Total input       $(Format-TokenDetail ([long]$breakdown.total_input_tokens))"
        "Fresh input       $(Format-TokenDetail ([long]$breakdown.fresh_input_tokens))"
        "Cache creation    $(Format-TokenDetail ([long]$breakdown.cache_creation_input_tokens))"
        "Cache read        $(Format-TokenDetail ([long]$breakdown.cache_read_input_tokens))"
        "Last output       $(Format-TokenDetail ([long]$breakdown.total_output_tokens))"
        "Remaining         $(Format-TokenDetail ([long]$breakdown.remaining_tokens))"
        ""
        "5-hour limit      $(if ([double]$limits.five_hour.used_percentage -ge 0) { '%' + [Math]::Round([double]$limits.five_hour.used_percentage) } else { '--' })"
        "Resets in         $(Format-ResetRemaining ([long]$limits.five_hour.resets_at))"
        "7-day limit       $(if ([double]$limits.seven_day.used_percentage -ge 0) { '%' + [Math]::Round([double]$limits.seven_day.used_percentage) } else { '--' })"
    ) -join "`n"
}

$EmptyBreakdown = [pscustomobject]@{ total_input_tokens = 0L; total_output_tokens = 0L; fresh_input_tokens = 0L; cache_creation_input_tokens = 0L; cache_read_input_tokens = 0L; context_window_size = 0L; remaining_tokens = 0L }
$EmptyRateLimits = [pscustomobject]@{ five_hour = [pscustomobject]@{ used_percentage = -1.0; resets_at = 0L }; seven_day = [pscustomobject]@{ used_percentage = -1.0; resets_at = 0L } }
$State = [pscustomobject]@{ level = 0.0; tokens = 0L; active = $false; stage = "RED DWARF"; project_root = ""; project_name = ""; breakdown = $EmptyBreakdown; rate_limits = $EmptyRateLimits }
$LastStateWrite = [datetime]::MinValue
$OverlayPosition = [pscustomobject]@{ x = 0.96; y = 0.06 }
$LastHostWindow = $null
$LastHostSignature = ""
$LastMassLayoutKey = ""
$LastDetailsText = ""
$NextStatePoll = 0.0
$CachedForegroundHandle = [IntPtr]::Zero
$CachedHostWindow = $null
$NextHostRefresh = 0.0

if (Test-Path -LiteralPath $PositionPath) {
    try {
        $savedPosition = [IO.File]::ReadAllText($PositionPath) | ConvertFrom-Json
        $OverlayPosition = [pscustomobject]@{
            x = [Math]::Min(1.0, [Math]::Max(0.0, [double]$savedPosition.x))
            y = [Math]::Min(1.0, [Math]::Max(0.0, [double]$savedPosition.y))
        }
    }
    catch { }
}

function Read-TokenState {
    if ($DemoLevel -ge 0.0) {
        $demoNormalized = [Math]::Min(1.0, [Math]::Max(0.0, $(if ($DemoLevel -gt 1.0) { $DemoLevel / 100.0 } else { $DemoLevel })))
        $demoTokens = [long][Math]::Round(200000.0 * $demoNormalized)
        $demoReset = [DateTimeOffset]::UtcNow.AddHours(2.4).ToUnixTimeSeconds()
        $script:State = [pscustomobject]@{
            level = $demoNormalized
            tokens = $demoTokens
            active = $true
            stage = Get-Stage $demoNormalized
            project_root = ""
            project_name = ""
            breakdown = [pscustomobject]@{ total_input_tokens = $demoTokens; total_output_tokens = 4200L; fresh_input_tokens = [long][Math]::Round($demoTokens * 0.12); cache_creation_input_tokens = [long][Math]::Round($demoTokens * 0.18); cache_read_input_tokens = [long][Math]::Round($demoTokens * 0.70); context_window_size = 200000L; remaining_tokens = 200000L - $demoTokens }
            rate_limits = [pscustomobject]@{ five_hour = [pscustomobject]@{ used_percentage = 61.0; resets_at = $demoReset }; seven_day = [pscustomobject]@{ used_percentage = 34.0; resets_at = [DateTimeOffset]::UtcNow.AddDays(3).ToUnixTimeSeconds() } }
        }
        return
    }
    if (-not (Test-Path -LiteralPath $StatePath)) {
        if ($Demo) {
            $script:DemoLevel = 0.95
            Read-TokenState
        }
        return
    }
    $item = Get-Item -LiteralPath $StatePath
    if ($item.LastWriteTimeUtc -eq $script:LastStateWrite) { return }
    try {
        $value = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
        $breakdown = if ($value.breakdown) { $value.breakdown } else { $script:EmptyBreakdown }
        $rateLimits = if ($value.rate_limits) { $value.rate_limits } else { $script:EmptyRateLimits }
        $script:State = [pscustomobject]@{
            level = [Math]::Min(1.0, [Math]::Max(0.0, [double]$value.level))
            tokens = [Math]::Max(0L, [long]$value.tokens)
            active = [bool]$value.active
            stage = [string]$value.stage
            project_root = [string]$value.project_root
            project_name = [string]$value.project_name
            breakdown = $breakdown
            rate_limits = $rateLimits
        }
        $script:LastStateWrite = $item.LastWriteTimeUtc
    }
    catch { }
}

function Get-IdeWindow {
    $handle = [TokenStarNative]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) { return $null }
    if ($script:OverlayHandle -ne [IntPtr]::Zero -and $handle -eq $script:OverlayHandle) {
        return $script:LastHostWindow
    }
    $now = if ($script:Stopwatch) { $script:Stopwatch.Elapsed.TotalSeconds } else { 0.0 }
    if ($handle -eq $script:CachedForegroundHandle -and $now -lt $script:NextHostRefresh) {
        return $script:CachedHostWindow
    }
    $script:CachedForegroundHandle = $handle
    $script:NextHostRefresh = $now + 0.50
    $processId = [uint32]0
    [void][TokenStarNative]::GetWindowThreadProcessId($handle, [ref]$processId)
    try { $process = Get-Process -Id $processId -ErrorAction Stop }
    catch { $script:CachedHostWindow = $null; return $null }
    $allowed = @("pycharm64", "pycharm", "idea64", "idea", "webstorm64", "webstorm", "rider64", "rider", "clion64", "clion", "goland64", "goland", "phpstorm64", "phpstorm", "rubymine64", "rubymine", "datagrip64", "datagrip", "studio64", "studio", "code", "cursor", "devenv", "eclipse")
    if (-not $Demo -and $allowed -notcontains $process.ProcessName.ToLowerInvariant()) {
        $script:CachedHostWindow = $null
        return $null
    }
    $rect = New-Object TokenStarNative+RECT
    if (-not [TokenStarNative]::GetWindowRect($handle, [ref]$rect)) {
        $script:CachedHostWindow = $null
        return $null
    }
    $dpi = [TokenStarNative]::GetDpiForWindow($handle)
    if ($dpi -le 0) { $dpi = 96 }
    $titleLength = [TokenStarNative]::GetWindowTextLength($handle)
    $titleBuffer = New-Object System.Text.StringBuilder([Math]::Max(1, $titleLength + 1))
    [void][TokenStarNative]::GetWindowText($handle, $titleBuffer, $titleBuffer.Capacity)
    $script:CachedHostWindow = [pscustomobject]@{ Handle = $handle; Rect = $rect; Scale = $dpi / 96.0; Title = $titleBuffer.ToString() }
    return $script:CachedHostWindow
}

function Test-ProjectWindow($HostWindow) {
    $projectName = [string]$State.project_name
    if ([string]::IsNullOrWhiteSpace($projectName)) { return $true }
    if ($null -eq $HostWindow -or [string]::IsNullOrWhiteSpace([string]$HostWindow.Title)) { return $false }
    return ([string]$HostWindow.Title).IndexOf($projectName, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-OverlayScale([double]$Fallback) {
    $source = [Windows.PresentationSource]::FromVisual($Window)
    if ($source -and $source.CompositionTarget) {
        $value = [double]$source.CompositionTarget.TransformToDevice.M11
        if ($value -gt 0) { return $value }
    }
    if ($Fallback -gt 0) { return $Fallback }
    return 1.0
}

function Set-WindowPosition($HostWindow) {
    if (-not $HostWindow -or -not $HostWindow.Rect) { return }
    $scale = Get-OverlayScale ([double]$HostWindow.Scale)
    $margin = 4.0
    $left = $HostWindow.Rect.Left / $scale + $margin
    $top = $HostWindow.Rect.Top / $scale + $margin
    $right = $HostWindow.Rect.Right / $scale - $margin
    $bottom = $HostWindow.Rect.Bottom / $scale - $margin
    $availableX = [Math]::Max(0.0, $right - $left - $Window.Width)
    $availableY = [Math]::Max(0.0, $bottom - $top - $Window.Height)
    $Window.Left = $left + $availableX * [double]$OverlayPosition.x
    $Window.Top = $top + $availableY * [double]$OverlayPosition.y
}

function Save-WindowPosition {
    $hostWindow = if ($script:LastHostWindow) { $script:LastHostWindow } else { Get-IdeWindow }
    if (-not $hostWindow -or -not $hostWindow.Rect) { return }
    $scale = Get-OverlayScale ([double]$hostWindow.Scale)
    $margin = 4.0
    $left = $hostWindow.Rect.Left / $scale + $margin
    $top = $hostWindow.Rect.Top / $scale + $margin
    $right = $hostWindow.Rect.Right / $scale - $margin
    $bottom = $hostWindow.Rect.Bottom / $scale - $margin
    $availableX = [Math]::Max(0.0, $right - $left - $Window.Width)
    $availableY = [Math]::Max(0.0, $bottom - $top - $Window.Height)
    $clampedLeft = [Math]::Min($left + $availableX, [Math]::Max($left, $Window.Left))
    $clampedTop = [Math]::Min($top + $availableY, [Math]::Max($top, $Window.Top))
    $Window.Left = $clampedLeft
    $Window.Top = $clampedTop
    $script:OverlayPosition = [pscustomobject]@{
        x = if ($availableX -gt 0) { ($clampedLeft - $left) / $availableX } else { 0.0 }
        y = if ($availableY -gt 0) { ($clampedTop - $top) / $availableY } else { 0.0 }
    }
    $json = ($script:OverlayPosition | ConvertTo-Json -Compress) + "`n"
    $temporary = $PositionPath + ".tmp"
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $PositionPath -Force
}

$OverlayHandle = [IntPtr]::Zero
$DragHandleActive = $false
$ClickThroughEnabled = $true
$DetailsOpen = $false
$DownArrow = [string][char]0x25BC
$UpArrow = [string][char]0x25B2
$DefaultPanelBorder = New-Object Windows.Media.SolidColorBrush((Convert-Color "#CC5F91BF"))
$HoverPanelBorder = New-Object Windows.Media.SolidColorBrush((Convert-Color "#FFFFFFFF"))

function Test-PointOverElement($Point, $Element, [double]$Padding = 0.0) {
    $left = [Windows.Controls.Canvas]::GetLeft($Element)
    $top = [Windows.Controls.Canvas]::GetTop($Element)
    $width = [Math]::Max($Element.ActualWidth, $Element.Width)
    $height = [Math]::Max($Element.ActualHeight, $Element.Height)
    return $Point.X -ge ($left - $Padding) -and $Point.X -le ($left + $width + $Padding) -and
           $Point.Y -ge ($top - $Padding) -and $Point.Y -le ($top + $height + $Padding)
}

function Update-HitTestMode {
    if ($script:OverlayHandle -eq [IntPtr]::Zero) { return }
    $point = New-Object TokenStarNative+POINT
    $overStar = $false
    $overPanel = $false
    if ($Window.Opacity -gt 0.01 -and [TokenStarNative]::GetCursorPos([ref]$point)) {
        $local = $Window.PointFromScreen((New-Object Windows.Point($point.X, $point.Y)))
        $overStar = Test-PointOverElement $local $DragHandle 7.0
        $overPanel = Test-PointOverElement $local $MassPanel 7.0
    }

    $script:DragHandleActive = $overStar
    $MassPanel.BorderBrush = if ($overPanel) { $HoverPanelBorder } else { $DefaultPanelBorder }
    $shouldClickThrough = -not ($overStar -or $overPanel)
    if ($shouldClickThrough -ne $script:ClickThroughEnabled) {
        $GWL_EXSTYLE = -20
        $WS_EX_TRANSPARENT = 0x20
        $WS_EX_NOACTIVATE = 0x08000000
        $style = [TokenStarNative]::GetWindowLong($script:OverlayHandle, $GWL_EXSTYLE)
        if ($shouldClickThrough) { $style = $style -bor $WS_EX_TRANSPARENT -bor $WS_EX_NOACTIVATE }
        else { $style = $style -band (-bnot $WS_EX_TRANSPARENT) -band (-bnot $WS_EX_NOACTIVATE) }
        [void][TokenStarNative]::SetWindowLong($script:OverlayHandle, $GWL_EXSTYLE, $style)
        $script:ClickThroughEnabled = $shouldClickThrough
    }
}

$DragHandle.Add_PreviewMouseLeftButtonDown({
    if ($_.ChangedButton -eq [Windows.Input.MouseButton]::Left) {
        try { $Window.DragMove() }
        finally {
            Save-WindowPosition
            if ($script:LastHostWindow -and $script:LastHostWindow.Handle) {
                [void][TokenStarNative]::SetForegroundWindow($script:LastHostWindow.Handle)
            }
        }
        $_.Handled = $true
    }
})

$DetailsButton.Add_Click({
    $script:DetailsOpen = -not $script:DetailsOpen
    $DetailsButton.Content = if ($script:DetailsOpen) { $script:UpArrow } else { $script:DownArrow }
    $DetailsPanel.Visibility = if ($script:DetailsOpen) { "Visible" } else { "Collapsed" }
    $DetailsPanel.Opacity = if ($script:DetailsOpen) { 1.0 } else { 0.0 }
    if ($script:LastHostWindow -and $script:LastHostWindow.Handle) {
        [void][TokenStarNative]::SetForegroundWindow($script:LastHostWindow.Handle)
    }
    $_.Handled = $true
})

$Stopwatch = [Diagnostics.Stopwatch]::StartNew()
function Update-Visual {
    if (-not $SelfTest -and (Test-Path -LiteralPath $StopPath)) {
        $Window.Close()
        return
    }
    $time = $Stopwatch.Elapsed.TotalSeconds
    if ($time -ge $script:NextStatePoll) {
        Read-TokenState
        $script:NextStatePoll = $time + 0.25
    }
    $level = [double]$State.level
    $stage = if ($State.stage) { [string]$State.stage } else { Get-Stage $level }

    $hostWindow = if ($SelfTest) { [pscustomobject]@{ Rect = $null; Scale = 1.0; Title = "" } } else { Get-IdeWindow }
    $visible = [bool]$State.active -and $null -ne $hostWindow -and (Test-ProjectWindow $hostWindow)
    $Window.Opacity = if ($visible -or $SelfTest) { 1.0 } else { 0.0 }
    $DragHandle.IsHitTestVisible = $visible -or $SelfTest
    $MassPanel.IsHitTestVisible = $visible -or $SelfTest
    if ($script:Timer) {
        $targetInterval = if ($visible) { 80 } else { 250 }
        if ($script:Timer.Interval.TotalMilliseconds -ne $targetInterval) {
            $script:Timer.Interval = [TimeSpan]::FromMilliseconds($targetInterval)
        }
    }
    if ($hostWindow -and $hostWindow.Rect) {
        $script:LastHostWindow = $hostWindow
        $signature = "$($hostWindow.Rect.Left),$($hostWindow.Rect.Top),$($hostWindow.Rect.Right),$($hostWindow.Rect.Bottom)"
        if ($signature -ne $script:LastHostSignature) {
            $script:LastHostSignature = $signature
            Set-WindowPosition $hostWindow
        }
    }
    if (-not $visible -and -not $SelfTest) { return }

    $isNormal = $stage -in @("RED DWARF", "MAIN SEQUENCE", "BLUE GIANT", "HYPERGIANT")
    $isHyper = $stage -eq "HYPERGIANT"
    $isNeutron = $stage -eq "NEUTRON STAR"
    $isQuasar = $stage -eq "QUASAR"

    $diameter = switch ($stage) {
        "RED DWARF" { 54.0 }
        "MAIN SEQUENCE" { 82.0 }
        "BLUE GIANT" { 112.0 }
        "HYPERGIANT" { 142.0 }
        "NEUTRON STAR" { 28.0 }
        default { 92.0 }
    }
    Set-CenteredSize $DragHandle ([Math]::Max(42.0, $diameter)) ([Math]::Max(42.0, $diameter))
    $colors = switch ($stage) {
        "RED DWARF" { @("#FFFF5A21", "#00A51005") }
        "MAIN SEQUENCE" { @("#FFFFD36B", "#00FF6A10") }
        "BLUE GIANT" { @("#FFB6E0FF", "#003A68FF") }
        "HYPERGIANT" { @("#FFFFFFB0", "#00FF8A16") }
        "NEUTRON STAR" { @("#FFDFFFFF", "#003B8CFF") }
        default { @("#FF000000", "#00000000") }
    }

    Set-CenteredSize $Glow ($diameter * 2.15) ($diameter * 2.15)
    Set-CenteredSize $Core $diameter $diameter
    $Core.Fill = Get-RadialBrush $colors[0] $colors[1]
    $Glow.Fill = Get-RadialBrush $colors[0] "#00000000"
    $Core.Opacity = if ($isNormal -or $isNeutron) { 1.0 } else { 0.0 }
    $Glow.Opacity = if ($isNormal) { 0.58 } elseif ($isNeutron) { 0.88 } else { 0.0 }

    Set-CenteredSize $Nebula ($diameter * 3.35) ($diameter * 3.35)
    $Nebula.Fill = Get-RadialBrush $colors[0] "#00000000"
    $Nebula.Opacity = if ($isNormal) { 0.18 + 0.08 * [Math]::Sin($time * 1.7) } elseif ($isNeutron) { 0.28 } else { 0.0 }

    $pulse = 0.5 + 0.5 * [Math]::Sin($time * 2.6)
    Set-CenteredSize $PulseRingInner ($diameter * (1.30 + 0.12 * $pulse)) ($diameter * (1.30 + 0.12 * $pulse))
    Set-CenteredSize $PulseRingOuter ($diameter * (1.72 + 0.20 * $pulse)) ($diameter * (1.72 + 0.20 * $pulse))
    $PulseRingInner.Stroke = Get-SolidBrush $colors[0]
    $PulseRingOuter.Stroke = Get-SolidBrush $colors[0]
    $PulseRingInner.Opacity = if ($isNormal -and -not $isHyper) { 0.34 * (1.0 - $pulse) } else { 0.0 }
    $PulseRingOuter.Opacity = if ($isNormal -and -not $isHyper) { 0.18 * $pulse } else { 0.0 }
    $stageBrush = Get-SolidBrush $colors[0]

    $rayRadius = $diameter * 0.52
    for ($index = 0; $index -lt $RayLines.Count; $index++) {
        $angle = $index * (360.0 / $RayLines.Count) + $time * (8.0 + $level * 18.0)
        $radians = $angle * [Math]::PI / 180.0
        $inner = $rayRadius * 0.90
        $outer = $rayRadius * (1.12 + 0.58 * (0.5 + 0.5 * [Math]::Sin($time * 2.1 + $index * 1.7)))
        $line = $RayLines[$index]
        $line.X1 = $CenterX + [Math]::Cos($radians) * $inner
        $line.Y1 = $CenterY + [Math]::Sin($radians) * $inner
        $line.X2 = $CenterX + [Math]::Cos($radians) * $outer
        $line.Y2 = $CenterY + [Math]::Sin($radians) * $outer
        $line.Stroke = $stageBrush
        $line.Opacity = if ($isNormal -and -not $isHyper) { 0.28 + 0.36 * $level } else { 0.0 }
    }

    for ($index = 0; $index -lt $SurfaceDots.Count; $index++) {
        $spot = $SurfaceDots[$index]
        if ($isNormal -and -not $isHyper) {
            $angle = $index * 2.39996 + $time * (0.34 + ($index % 3) * 0.11)
            $radius = $diameter * (0.10 + 0.31 * (($index % 7) / 7.0))
            [Windows.Controls.Canvas]::SetLeft($spot, $CenterX + [Math]::Cos($angle) * $radius - $spot.Width / 2.0)
            [Windows.Controls.Canvas]::SetTop($spot, $CenterY + [Math]::Sin($angle) * $radius - $spot.Height / 2.0)
            $spot.Fill = $stageBrush
            $spot.Opacity = 0.18 + 0.34 * (0.5 + 0.5 * [Math]::Sin($time * 2.2 + $index))
        }
        else { $spot.Opacity = 0.0 }
    }

    Set-CenteredSize $HaloInner ($diameter * 1.42) ($diameter * 1.42)
    Set-CenteredSize $HaloOuter ($diameter * 1.85) ($diameter * 1.85)
    $HaloInner.Opacity = if ($isHyper) { 0.88 } else { 0.0 }
    $HaloOuter.Opacity = if ($isHyper) { 0.62 } else { 0.0 }

    Set-CenteredSize $NeutronBeamGlow 360 28
    Set-CenteredSize $NeutronBeam 350 6
    $NeutronAngle = ($time * 572.9578) % 360.0
    $NeutronBeam.RenderTransform.Angle = $NeutronAngle
    $NeutronBeamGlow.RenderTransform.Angle = $NeutronAngle
    $NeutronBeam.Opacity = if ($isNeutron) { 1.0 } else { 0.0 }
    $NeutronBeamGlow.Opacity = if ($isNeutron) { 0.92 } else { 0.0 }

    Set-CenteredSize $JetAura 94 360
    Set-CenteredSize $JetGlow 46 350
    Set-CenteredSize $JetCore 10 342
    Set-CenteredSize $DiskAura 330 88
    Set-CenteredSize $DiskOuter 302 72
    Set-CenteredSize $DiskGlow 270 62
    Set-CenteredSize $Disk 250 46
    Set-CenteredSize $DiskHot 220 34
    Set-CenteredSize $BlackCore 92 92
    $quasarOpacity = if ($isQuasar) { 1.0 } else { 0.0 }
    $JetAura.Opacity = $quasarOpacity * (0.44 + 0.12 * [Math]::Sin($time * 8.0))
    $JetGlow.Opacity = $quasarOpacity * 0.92
    $JetCore.Opacity = $quasarOpacity
    $DiskAura.Opacity = $quasarOpacity * (0.56 + 0.12 * [Math]::Sin($time * 5.0))
    $DiskOuter.Opacity = $quasarOpacity * 0.90
    $DiskGlow.Opacity = $quasarOpacity * 0.85
    $Disk.Opacity = $quasarOpacity
    $DiskHot.Opacity = $quasarOpacity
    $BlackCore.Opacity = $quasarOpacity
    $DiskFrontGlow.Opacity = $quasarOpacity * 0.88
    $DiskFront.Opacity = $quasarOpacity
    $spin = ($time * 600.0 * 360.0) % 360.0
    $DiskOuter.StrokeDashOffset = -$spin / 18.0
    $Disk.StrokeDashOffset = $spin / 24.0
    $DiskGlow.StrokeDashOffset = -$spin / 40.0
    $DiskHot.StrokeDashOffset = $spin / 13.0
    $DiskFrontGlow.StrokeDashOffset = -$spin / 24.0
    $DiskFront.StrokeDashOffset = $spin / 24.0

    for ($index = 0; $index -lt $ParticleDots.Count; $index++) {
        $dot = $ParticleDots[$index]
        $dot.Opacity = 0.0
        if ($isNormal -and -not $isHyper) {
            $travel = ($time * (0.16 + ($index % 5) * 0.018) + $index * 0.6180339) % 1.0
            $angle = $index * 2.39996 + $time * (0.16 + $level * 0.25)
            $radius = $diameter * (0.54 + 1.20 * $travel)
            [Windows.Controls.Canvas]::SetLeft($dot, $CenterX + [Math]::Cos($angle) * $radius - $dot.Width / 2.0)
            [Windows.Controls.Canvas]::SetTop($dot, $CenterY + [Math]::Sin($angle) * $radius - $dot.Height / 2.0)
            $dot.Fill = $stageBrush
            $dot.Opacity = (1.0 - $travel) * (0.30 + 0.45 * $level)
        }
        elseif ($isNeutron -and $index -lt 20) {
            $travel = ($time * (1.8 + ($index % 4) * 0.13) + $index / 20.0) % 1.0
            $distance = ($travel - 0.5) * 340.0
            $radians = $NeutronAngle * [Math]::PI / 180.0
            $jitter = [Math]::Sin($time * 18.0 + $index) * 2.5
            $x = $CenterX + [Math]::Cos($radians) * $distance - [Math]::Sin($radians) * $jitter
            $y = $CenterY + [Math]::Sin($radians) * $distance + [Math]::Cos($radians) * $jitter
            [Windows.Controls.Canvas]::SetLeft($dot, $x - $dot.Width / 2.0)
            [Windows.Controls.Canvas]::SetTop($dot, $y - $dot.Height / 2.0)
            $dot.Fill = [Windows.Media.Brushes]::White
            $dot.Opacity = 0.28 + 0.70 * [Math]::Sin([Math]::PI * $travel)
        }
        elseif ($isQuasar) {
            if ($index -lt 30) {
                $direction = if ($index % 2 -eq 0) { 1.0 } else { -1.0 }
                $angle = $index * 2.39996 + $direction * $time * (12.0 + ($index % 6))
                $radius = 76.0 + ($index % 9) * 11.0
                $x0 = [Math]::Cos($angle) * $radius
                $y0 = [Math]::Sin($angle) * (13.0 + ($index % 5) * 2.8)
                $tilt = -12.0 * [Math]::PI / 180.0
                $x = $CenterX + $x0 * [Math]::Cos($tilt) - $y0 * [Math]::Sin($tilt)
                $y = $CenterY + $x0 * [Math]::Sin($tilt) + $y0 * [Math]::Cos($tilt)
                [Windows.Controls.Canvas]::SetLeft($dot, $x - $dot.Width / 2.0)
                [Windows.Controls.Canvas]::SetTop($dot, $y - $dot.Height / 2.0)
                $dot.Fill = if ($index % 3 -eq 0) { [Windows.Media.Brushes]::White } elseif ($index % 3 -eq 1) { [Windows.Media.Brushes]::DeepPink } else { [Windows.Media.Brushes]::Orange }
                $dot.Opacity = 0.42 + 0.55 * (0.5 + 0.5 * [Math]::Sin($time * 13.0 + $index))
            }
            else {
                $travel = ($time * 1.9 + ($index - 30) / 6.0) % 1.0
                $distance = ($travel - 0.5) * 350.0
                $axis = -102.0 * [Math]::PI / 180.0
                $jitter = [Math]::Sin($time * 22.0 + $index) * (4.0 + 8.0 * [Math]::Abs($travel - 0.5))
                $x = $CenterX + [Math]::Cos($axis) * $distance - [Math]::Sin($axis) * $jitter
                $y = $CenterY + [Math]::Sin($axis) * $distance + [Math]::Cos($axis) * $jitter
                [Windows.Controls.Canvas]::SetLeft($dot, $x - $dot.Width / 2.0)
                [Windows.Controls.Canvas]::SetTop($dot, $y - $dot.Height / 2.0)
                $dot.Fill = [Windows.Media.Brushes]::White
                $dot.Opacity = 0.34 + 0.64 * [Math]::Sin([Math]::PI * $travel)
            }
        }
    }

    $massLabel = "MASS $(Format-Mass ([long]$State.tokens))"
    $rateSummary = Get-RateSummary
    $detailsContent = Get-DetailsText
    if ($detailsContent -ne $script:LastDetailsText) {
        $script:LastDetailsText = $detailsContent
        $DetailsText.Text = $detailsContent
    }
    $massLayoutKey = "$massLabel|$stage|$rateSummary"
    if ($massLayoutKey -ne $script:LastMassLayoutKey) {
        $script:LastMassLayoutKey = $massLayoutKey
        $MassText.Text = $massLabel
        $RateText.Text = " | $rateSummary"
        $MassPanel.Measure((New-Object Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
        $panelWidth = [Math]::Max(112.0, $MassPanel.DesiredSize.Width)
        $MassPanel.Width = $panelWidth
        $panelLeft = $CenterX - $panelWidth / 2.0 - $(if ($isQuasar) { 100 } else { 0 })
        $panelTop = $CenterY + [Math]::Max(58.0, $diameter * 0.70)
        [Windows.Controls.Canvas]::SetLeft($MassPanel, $panelLeft)
        [Windows.Controls.Canvas]::SetTop($MassPanel, $panelTop)
        [Windows.Controls.Canvas]::SetLeft($DetailsPanel, [Math]::Max(4.0, [Math]::Min($Window.Width - $DetailsPanel.Width - 4.0, $panelLeft + $panelWidth - $DetailsPanel.Width)))
        [Windows.Controls.Canvas]::SetTop($DetailsPanel, $panelTop + 38.0)
    }
    $MassPanel.Opacity = if ($visible -or $SelfTest) { 1.0 } else { 0.0 }
}

$Window.Add_SourceInitialized({
    $helper = New-Object Windows.Interop.WindowInteropHelper($Window)
    $handle = $helper.Handle
    $script:OverlayHandle = $handle
    $GWL_EXSTYLE = -20
    $WS_EX_TRANSPARENT = 0x20
    $WS_EX_TOOLWINDOW = 0x80
    $WS_EX_NOACTIVATE = 0x08000000
    $style = [TokenStarNative]::GetWindowLong($handle, $GWL_EXSTYLE)
    [void][TokenStarNative]::SetWindowLong($handle, $GWL_EXSTYLE, $style -bor $WS_EX_TRANSPARENT -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE)
    $script:ClickThroughEnabled = $true

    $script:WindowHook = [Windows.Interop.HwndSourceHook]{
        param($hwnd, $message, $wParam, $lParam, [ref]$handled)
        if ($message -eq 0x0084) {
            $handled.Value = $true
            if ($script:DragHandleActive) { return [IntPtr]1 }
            return [IntPtr](-1)
        }
        if ($message -eq 0x0232) {
            Save-WindowPosition
        }
        return [IntPtr]::Zero
    }
    $source = [Windows.Interop.HwndSource]::FromHwnd($handle)
    $source.AddHook($script:WindowHook)
})

Read-TokenState
Update-Visual
if ($SelfTest) {
    $State.project_name = "ScopedProject"
    if (-not (Test-ProjectWindow ([pscustomobject]@{ Title = "main.py - ScopedProject - PyCharm" }))) {
        throw "Token Star overlay project-title match self-test failed."
    }
    if (Test-ProjectWindow ([pscustomobject]@{ Title = "main.py - OtherProject - PyCharm" })) {
        throw "Token Star overlay project-title isolation self-test failed."
    }
    Write-Output "Token Star overlay self-test OK"
    if ($CreatedNew) { $OverlayMutex.ReleaseMutex() }
    $OverlayMutex.Dispose()
    exit 0
}

[GC]::Collect()
[GC]::WaitForPendingFinalizers()
[GC]::Collect()

$Timer = New-Object Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(80)
$Timer.Add_Tick({ Update-Visual; Update-HitTestMode })
$Timer.Start()
try { [void]$Window.ShowDialog() }
finally {
    try {
        if (Test-Path -LiteralPath $PidPath) {
            $pidRecord = [IO.File]::ReadAllText($PidPath) | ConvertFrom-Json
            if ([int]$pidRecord.pid -eq $PID) { Remove-Item -LiteralPath $PidPath -Force }
        }
    }
    catch { }
    Remove-Item -LiteralPath ($PidPath + ".tmp") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StopPath -Force -ErrorAction SilentlyContinue
    if ($CreatedNew) { $OverlayMutex.ReleaseMutex() }
    $OverlayMutex.Dispose()
}
