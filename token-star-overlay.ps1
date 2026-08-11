[CmdletBinding()]
param(
    [string]$StatePath,
    [switch]$SelfTest,
    [switch]$Demo
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $ScriptRoot "token-state.json"
}
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$CreatedNew = $false
$OverlayMutex = New-Object System.Threading.Mutex($true, "Local\ClaudeCodeTokenStarOverlay", [ref]$CreatedNew)
if (-not $CreatedNew -and -not $SelfTest) {
    $OverlayMutex.Dispose()
    exit 0
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TokenStarNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll", SetLastError=true)] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
}
"@

[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="500" Height="380" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ShowActivated="False" Focusable="False" ResizeMode="NoResize">
  <Canvas Name="Root" Width="500" Height="380" IsHitTestVisible="False">
    <Canvas Name="Stars" />
    <Canvas Name="Rays" />

    <Ellipse Name="HaloOuter" Stroke="#66FFB52E" StrokeThickness="3" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="7" /></Ellipse.Effect>
    </Ellipse>
    <Ellipse Name="HaloInner" Stroke="#AAFFE47A" StrokeThickness="4" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="5" /></Ellipse.Effect>
    </Ellipse>

    <Rectangle Name="JetGlow" Width="46" Height="330" RadiusX="18" RadiusY="18" Opacity="0"
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
      <Rectangle.Effect><BlurEffect Radius="18" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="-12" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="JetCore" Width="11" Height="320" RadiusX="5" RadiusY="5" Opacity="0"
               Fill="#EFFFFFFF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="5" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="-12" /></Rectangle.RenderTransform>
    </Rectangle>

    <Rectangle Name="NeutronBeamGlow" Width="360" Height="28" RadiusX="12" RadiusY="12" Opacity="0"
               Fill="#884AA8FF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="14" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="NeutronBeam" Width="350" Height="6" RadiusX="3" RadiusY="3" Opacity="0"
               Fill="#EEEAFFFF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="3" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>

    <Ellipse Name="Glow" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="30" /></Ellipse.Effect>
    </Ellipse>
    <Ellipse Name="Core" Opacity="0" />

    <Ellipse Name="DiskGlow" Width="270" Height="62" Stroke="#BBFF6B26" StrokeThickness="18"
             StrokeDashArray="3 1 1 1" Opacity="0" RenderTransformOrigin="0.5,0.5">
      <Ellipse.Effect><BlurEffect Radius="13" /></Ellipse.Effect>
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
      <Ellipse.Effect><BlurEffect Radius="4" /></Ellipse.Effect>
      <Ellipse.RenderTransform><RotateTransform Angle="-12" /></Ellipse.RenderTransform>
    </Ellipse>
    <Ellipse Name="BlackCore" Width="92" Height="92" Fill="#FF010205" Stroke="#FFFFC85A"
             StrokeThickness="5" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="3" /></Ellipse.Effect>
    </Ellipse>

    <Border Name="MassPanel" Background="#EE03060C" BorderBrush="#994C7199"
            BorderThickness="1" CornerRadius="3" Padding="8,4" Opacity="0">
      <TextBlock Name="MassText" Text="MASS 0K" Foreground="#FFF8FCFF"
                 FontFamily="Consolas" FontWeight="Bold" FontSize="16" />
    </Border>
  </Canvas>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$Root = $Window.FindName("Root")
$Stars = $Window.FindName("Stars")
$Rays = $Window.FindName("Rays")
$HaloOuter = $Window.FindName("HaloOuter")
$HaloInner = $Window.FindName("HaloInner")
$JetGlow = $Window.FindName("JetGlow")
$JetCore = $Window.FindName("JetCore")
$NeutronBeamGlow = $Window.FindName("NeutronBeamGlow")
$NeutronBeam = $Window.FindName("NeutronBeam")
$Glow = $Window.FindName("Glow")
$Core = $Window.FindName("Core")
$DiskGlow = $Window.FindName("DiskGlow")
$Disk = $Window.FindName("Disk")
$BlackCore = $Window.FindName("BlackCore")
$MassPanel = $Window.FindName("MassPanel")
$MassText = $Window.FindName("MassText")

$CenterX = 310.0
$CenterY = 165.0
$Random = New-Object System.Random 164
$StarDots = @()
for ($index = 0; $index -lt 46; $index++) {
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
for ($index = 0; $index -lt 30; $index++) {
    $line = New-Object Windows.Shapes.Line
    $line.StrokeThickness = if ($index % 3 -eq 0) { 2.0 } else { 1.0 }
    $line.Opacity = 0.0
    $line.Effect = New-Object Windows.Media.Effects.BlurEffect -Property @{ Radius = 2.5 }
    [void]$Rays.Children.Add($line)
    $RayLines += $line
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
    return $brush
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
    if ($Tokens -ge 1000000) { return "{0:0.00}M" -f ($Tokens / 1000000.0) }
    if ($Tokens -ge 1000) { return "{0:0}K" -f ($Tokens / 1000.0) }
    return [string]$Tokens
}

$State = [pscustomobject]@{ level = 0.0; tokens = 0L; active = $false; stage = "RED DWARF" }
$LastStateWrite = [datetime]::MinValue

function Read-TokenState {
    if ($Demo) {
        $script:State = [pscustomobject]@{ level = 0.95; tokens = 190000L; active = $true; stage = "QUASAR" }
        return
    }
    if (-not (Test-Path -LiteralPath $StatePath)) { return }
    $item = Get-Item -LiteralPath $StatePath
    if ($item.LastWriteTimeUtc -eq $script:LastStateWrite) { return }
    try {
        $value = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
        $script:State = [pscustomobject]@{
            level = [Math]::Min(1.0, [Math]::Max(0.0, [double]$value.level))
            tokens = [Math]::Max(0L, [long]$value.tokens)
            active = [bool]$value.active
            stage = [string]$value.stage
        }
        $script:LastStateWrite = $item.LastWriteTimeUtc
    }
    catch { }
}

function Get-IdeWindow {
    $handle = [TokenStarNative]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) { return $null }
    $processId = [uint32]0
    [void][TokenStarNative]::GetWindowThreadProcessId($handle, [ref]$processId)
    try { $process = Get-Process -Id $processId -ErrorAction Stop }
    catch { return $null }
    $allowed = @("pycharm64", "pycharm", "idea64", "idea", "webstorm64", "rider64", "code", "cursor", "devenv", "eclipse")
    if ($allowed -notcontains $process.ProcessName.ToLowerInvariant()) { return $null }
    $rect = New-Object TokenStarNative+RECT
    if (-not [TokenStarNative]::GetWindowRect($handle, [ref]$rect)) { return $null }
    $dpi = [TokenStarNative]::GetDpiForWindow($handle)
    if ($dpi -le 0) { $dpi = 96 }
    return [pscustomobject]@{ Rect = $rect; Scale = $dpi / 96.0 }
}

$Stopwatch = [Diagnostics.Stopwatch]::StartNew()
function Update-Visual {
    Read-TokenState
    $level = [double]$State.level
    $stage = if ($State.stage) { [string]$State.stage } else { Get-Stage $level }
    $time = $Stopwatch.Elapsed.TotalSeconds

    $hostWindow = if ($SelfTest) { [pscustomobject]@{ Rect = $null; Scale = 1.0 } } else { Get-IdeWindow }
    $visible = [bool]$State.active -and $null -ne $hostWindow
    $Window.Opacity = if ($visible -or $SelfTest) { 1.0 } else { 0.0 }
    if ($hostWindow -and $hostWindow.Rect) {
        $source = [Windows.PresentationSource]::FromVisual($Window)
        $scale = if ($source -and $source.CompositionTarget) {
            [double]$source.CompositionTarget.TransformToDevice.M11
        }
        else { [double]$hostWindow.Scale }
        if ($scale -le 0) { $scale = 1.0 }
        $Window.Left = $hostWindow.Rect.Right / $scale - $Window.Width - 18
        $Window.Top = $hostWindow.Rect.Top / $scale + 62
    }

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
    $Core.Fill = New-RadialBrush $colors[0] $colors[1]
    $Glow.Fill = New-RadialBrush $colors[0] "#00000000"
    $Core.Opacity = if ($isNormal -or $isNeutron) { 1.0 } else { 0.0 }
    $Glow.Opacity = if ($isNormal) { 0.58 } elseif ($isNeutron) { 0.88 } else { 0.0 }

    $rayRadius = $diameter * 0.52
    for ($index = 0; $index -lt $RayLines.Count; $index++) {
        $angle = $index * 12.0 + $time * (8.0 + $level * 18.0)
        $radians = $angle * [Math]::PI / 180.0
        $inner = $rayRadius * 0.90
        $outer = $rayRadius * (1.12 + 0.58 * (0.5 + 0.5 * [Math]::Sin($time * 2.1 + $index * 1.7)))
        $line = $RayLines[$index]
        $line.X1 = $CenterX + [Math]::Cos($radians) * $inner
        $line.Y1 = $CenterY + [Math]::Sin($radians) * $inner
        $line.X2 = $CenterX + [Math]::Cos($radians) * $outer
        $line.Y2 = $CenterY + [Math]::Sin($radians) * $outer
        $line.Stroke = New-Object Windows.Media.SolidColorBrush((Convert-Color $colors[0]))
        $line.Opacity = if ($isNormal -and -not $isHyper) { 0.28 + 0.36 * $level } else { 0.0 }
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

    Set-CenteredSize $JetGlow 46 330
    Set-CenteredSize $JetCore 11 320
    Set-CenteredSize $DiskGlow 270 62
    Set-CenteredSize $Disk 250 46
    Set-CenteredSize $BlackCore 92 92
    $quasarOpacity = if ($isQuasar) { 1.0 } else { 0.0 }
    $JetGlow.Opacity = $quasarOpacity * 0.92
    $JetCore.Opacity = $quasarOpacity
    $DiskGlow.Opacity = $quasarOpacity * 0.85
    $Disk.Opacity = $quasarOpacity
    $BlackCore.Opacity = $quasarOpacity
    $spin = ($time * 600.0 * 360.0) % 360.0
    $Disk.StrokeDashOffset = $spin / 24.0
    $DiskGlow.StrokeDashOffset = -$spin / 40.0

    $MassText.Text = "MASS $(Format-Mass ([long]$State.tokens))"
    $MassPanel.Measure((New-Object Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
    $panelWidth = [Math]::Max(112.0, $MassPanel.DesiredSize.Width)
    $MassPanel.Width = $panelWidth
    [Windows.Controls.Canvas]::SetLeft($MassPanel, $CenterX - $panelWidth / 2.0 - $(if ($isQuasar) { 145 } else { 0 }))
    [Windows.Controls.Canvas]::SetTop($MassPanel, $CenterY + [Math]::Max(58.0, $diameter * 0.70))
    $MassPanel.Opacity = if ($State.active) { 1.0 } else { 0.0 }

    for ($index = 0; $index -lt $StarDots.Count; $index++) {
        $StarDots[$index].Opacity = if ($State.active) {
            0.10 + 0.34 * (0.5 + 0.5 * [Math]::Sin($time * (0.8 + ($index % 5) * 0.17) + $index))
        }
        else { 0.0 }
    }
}

$Window.Add_SourceInitialized({
    $helper = New-Object Windows.Interop.WindowInteropHelper($Window)
    $handle = $helper.Handle
    $GWL_EXSTYLE = -20
    $WS_EX_TRANSPARENT = 0x20
    $WS_EX_TOOLWINDOW = 0x80
    $WS_EX_NOACTIVATE = 0x08000000
    $style = [TokenStarNative]::GetWindowLong($handle, $GWL_EXSTYLE)
    [void][TokenStarNative]::SetWindowLong($handle, $GWL_EXSTYLE, $style -bor $WS_EX_TRANSPARENT -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE)
})

Read-TokenState
Update-Visual
if ($SelfTest) {
    Write-Output "Token Star overlay self-test OK"
    if ($CreatedNew) { $OverlayMutex.ReleaseMutex() }
    $OverlayMutex.Dispose()
    exit 0
}

$Timer = New-Object Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(33)
$Timer.Add_Tick({ Update-Visual })
$Timer.Start()
try { [void]$Window.ShowDialog() }
finally {
    if ($CreatedNew) { $OverlayMutex.ReleaseMutex() }
    $OverlayMutex.Dispose()
}
