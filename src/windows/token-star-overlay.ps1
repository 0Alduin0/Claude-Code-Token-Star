[CmdletBinding()]
param(
    [string]$StatePath,
    [string]$PositionPath,
    [string]$PidPath,
    [string]$StopPath,
    [string]$CapturePath,
    [switch]$CaptureDetails,
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

$mutexHashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
try {
    $mutexBytes = $mutexHashAlgorithm.ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($PSScriptRoot).ToUpperInvariant())
    )
}
finally { $mutexHashAlgorithm.Dispose() }
$mutexSuffix = (($mutexBytes[0..7] | ForEach-Object { $_.ToString("x2") }) -join "")
$CreatedNew = $false
$OverlayMutex = New-Object System.Threading.Mutex($true, "Local\ClaudeCodeTokenStarOverlay-$mutexSuffix", [ref]$CreatedNew)
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
    [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr process);
}
"@

[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="700" Height="760" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ShowActivated="False" Focusable="False" ResizeMode="NoResize">
  <Canvas Name="Root" Width="700" Height="760">
    <Canvas Name="VisualLayer" Width="500" Height="500" Canvas.Left="40" Canvas.Top="95"
            IsHitTestVisible="False">
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
      <Rectangle.Effect><BlurEffect Radius="4" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="-12" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="JetCore" Width="10" Height="342" RadiusX="5" RadiusY="5" Opacity="0"
               Fill="#EFFFFFFF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="1" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="-12" /></Rectangle.RenderTransform>
    </Rectangle>

    <Rectangle Name="NeutronBeamAura" Width="410" Height="66" RadiusX="30" RadiusY="30" Opacity="0"
               RenderTransformOrigin="0.5,0.5">
      <Rectangle.Fill>
        <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
          <GradientStop Color="#00478EFF" Offset="0" />
          <GradientStop Color="#995AB8FF" Offset="0.26" />
          <GradientStop Color="#EEEAFFFF" Offset="0.5" />
          <GradientStop Color="#995AB8FF" Offset="0.74" />
          <GradientStop Color="#00478EFF" Offset="1" />
        </LinearGradientBrush>
      </Rectangle.Fill>
      <Rectangle.Effect><BlurEffect Radius="8" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="NeutronBeamGlow" Width="390" Height="34" RadiusX="15" RadiusY="15" Opacity="0"
               Fill="#AA4AA8FF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="4" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="NeutronBeam" Width="382" Height="7" RadiusX="3" RadiusY="3" Opacity="0"
               Fill="#EEEAFFFF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.Effect><BlurEffect Radius="1" /></Rectangle.Effect>
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>
    <Rectangle Name="NeutronBeamHot" Width="372" Height="2" RadiusX="1" RadiusY="1" Opacity="0"
               Fill="#FFFFFFFF" RenderTransformOrigin="0.5,0.5">
      <Rectangle.RenderTransform><RotateTransform Angle="0" /></Rectangle.RenderTransform>
    </Rectangle>

    <Path Name="CoronaShellOuter" Opacity="0">
      <Path.Effect><BlurEffect Radius="4" /></Path.Effect>
    </Path>
    <Path Name="CoronaShellInner" Opacity="0">
      <Path.Effect><BlurEffect Radius="2" /></Path.Effect>
    </Path>
    <Ellipse Name="Glow" Opacity="0">
      <Ellipse.Effect><BlurEffect Radius="8" /></Ellipse.Effect>
    </Ellipse>
    <Canvas Name="Prominences" />
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
      <Ellipse.Effect><BlurEffect Radius="3" /></Ellipse.Effect>
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
      <Path.Effect><BlurEffect Radius="3" /></Path.Effect>
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
    </Canvas>

    <Ellipse Name="DragHandle" Width="92" Height="92" Fill="#01000000"
             Cursor="SizeAll" />

    <Border Name="MassPanel" Background="#F20A111B" BorderBrush="#CC5F91BF"
            BorderThickness="1" CornerRadius="7" Padding="7,4" Opacity="0">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="24" />
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Name="MassText" Text="MASS 0K" Foreground="#FFF8FCFF"
                   FontFamily="Segoe UI" FontWeight="SemiBold" FontSize="12" VerticalAlignment="Center" />
        <TextBlock Grid.Column="1" Name="RateText" Text=" | 5H -- | --" Foreground="#FFA9C4DF"
                   FontFamily="Segoe UI" FontSize="10" VerticalAlignment="Center" Margin="3,0,3,0" />
        <Button Grid.Column="2" Name="DetailsButton" Content="&#x25BC;" ToolTip="Show token details"
                Foreground="#FFFFFFFF" Background="#FF14283B" BorderBrush="#FF527CA4"
                BorderThickness="1,0,0,0" MinWidth="24" FontWeight="Bold"
                FontFamily="Segoe UI" FontSize="10" Padding="4,0" Margin="0,-4,-7,-4"
                Cursor="Hand" Focusable="False" />
      </Grid>
    </Border>
    <Border Name="DetailsPanel" Width="300" Background="#F20A111B" BorderBrush="#AA4C7199"
            BorderThickness="1" CornerRadius="7" Padding="10,8" Opacity="0"
            Visibility="Collapsed">
      <StackPanel>
        <TextBlock Name="DetailsText" Foreground="#FFE8F4FF" FontFamily="Segoe UI"
                   FontSize="11" LineHeight="16" TextAlignment="Center" />
        <Border Height="1" Background="#664C7199" Margin="0,6,0,5" />
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="82" />
            <ColumnDefinition Width="*" />
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="STAR STAGE" Foreground="#FFA9C4DF"
                     FontFamily="Segoe UI" FontSize="10" VerticalAlignment="Center" />
          <ComboBox Grid.Column="1" Name="StageModeComboBox" Height="24"
                    Foreground="#FF102030" Background="#FFF4F8FC" BorderBrush="#FF527CA4"
                    FontFamily="Segoe UI" FontSize="10" Cursor="Hand" Focusable="False">
            <ComboBoxItem Content="Auto (token based)" Tag="AUTO" />
            <ComboBoxItem Content="Red Dwarf" Tag="RED DWARF" />
            <ComboBoxItem Content="Main Sequence" Tag="MAIN SEQUENCE" />
            <ComboBoxItem Content="Blue Giant" Tag="BLUE GIANT" />
            <ComboBoxItem Content="Hypergiant" Tag="HYPERGIANT" />
            <ComboBoxItem Content="Neutron Star" Tag="NEUTRON STAR" />
            <ComboBoxItem Content="Quasar" Tag="QUASAR" />
          </ComboBox>
        </Grid>
        <CheckBox Name="GrowWithTokensCheckBox" Content="Grow with token usage"
                  Foreground="#FFE8F4FF" FontFamily="Segoe UI" FontSize="10"
                  Margin="0,5,0,0" Cursor="Hand" Focusable="False" />
        <Border Height="1" Background="#664C7199" Margin="0,5,0,5" />
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*" />
            <ColumnDefinition Width="34" />
            <ColumnDefinition Width="34" />
            <ColumnDefinition Width="34" />
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="STAR SIZE" Foreground="#FFA9C4DF"
                     FontFamily="Segoe UI" FontSize="10" VerticalAlignment="Center" />
          <Button Grid.Column="1" Name="Scale1Button" Content="1x" Margin="1,0"
                  Foreground="#FFE8F4FF" Background="#FF0D1A27" BorderBrush="#FF527CA4"
                  FontFamily="Segoe UI" FontSize="10" Padding="2" Cursor="Hand" Focusable="False" />
          <Button Grid.Column="2" Name="Scale2Button" Content="2x" Margin="1,0"
                  Foreground="#FFE8F4FF" Background="#FF0D1A27" BorderBrush="#FF527CA4"
                  FontFamily="Segoe UI" FontSize="10" Padding="2" Cursor="Hand" Focusable="False" />
          <Button Grid.Column="3" Name="Scale3Button" Content="3x" Margin="1,0"
                  Foreground="#FFE8F4FF" Background="#FF0D1A27" BorderBrush="#FF527CA4"
                  FontFamily="Segoe UI" FontSize="10" Padding="2" Cursor="Hand" Focusable="False" />
        </Grid>
        <Border Height="1" Background="#664C7199" Margin="0,5,0,4" />
        <CheckBox Name="LockPositionCheckBox" Content="Lock position" Foreground="#FFE8F4FF"
                  FontFamily="Segoe UI" FontSize="10" Cursor="Hand" Focusable="False" />
      </StackPanel>
    </Border>
  </Canvas>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()
$reader = $null
$Xaml = $null
$Root = $Window.FindName("Root")
$VisualLayer = $Window.FindName("VisualLayer")
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
$NeutronBeamAura = $Window.FindName("NeutronBeamAura")
$NeutronBeamGlow = $Window.FindName("NeutronBeamGlow")
$NeutronBeam = $Window.FindName("NeutronBeam")
$NeutronBeamHot = $Window.FindName("NeutronBeamHot")
$CoronaShellOuter = $Window.FindName("CoronaShellOuter")
$CoronaShellInner = $Window.FindName("CoronaShellInner")
$Glow = $Window.FindName("Glow")
$Prominences = $Window.FindName("Prominences")
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
$StageModeComboBox = $Window.FindName("StageModeComboBox")
$GrowWithTokensCheckBox = $Window.FindName("GrowWithTokensCheckBox")
$Scale1Button = $Window.FindName("Scale1Button")
$Scale2Button = $Window.FindName("Scale2Button")
$Scale3Button = $Window.FindName("Scale3Button")
$LockPositionCheckBox = $Window.FindName("LockPositionCheckBox")

foreach ($visual in @(
    $Stars, $Nebula, $PulseRingOuter, $PulseRingInner, $Rays, $Particles,
    $HaloOuter, $HaloInner, $JetAura, $JetGlow, $JetCore,
    $NeutronBeamAura, $NeutronBeamGlow, $NeutronBeam, $NeutronBeamHot,
    $CoronaShellOuter, $CoronaShellInner, $Glow, $Prominences, $Core, $Surface,
    $DiskAura, $DiskOuter, $DiskGlow, $Disk, $DiskHot, $BlackCore,
    $DiskFrontGlow, $DiskFront
)) {
    $visual.IsHitTestVisible = $false
}
$DragHandle.IsHitTestVisible = $true
$MassPanel.IsHitTestVisible = $true
$DetailsPanel.IsHitTestVisible = $true

$CanvasWidth = 700.0
$CanvasHeight = 760.0
$CenterX = 350.0
$CenterY = 260.0
$VisualCenterX = 310.0
$VisualCenterY = 165.0
$Random = New-Object System.Random 164
$StarDots = @()
for ($index = 0; $index -lt 12; $index++) {
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
for ($index = 0; $index -lt 16; $index++) {
    $line = New-Object Windows.Shapes.Line
    $line.StrokeThickness = if ($index % 12 -eq 0) { 3.2 } elseif ($index % 4 -eq 0) { 1.8 } else { 0.9 }
    $line.Opacity = 0.0
    [void]$Rays.Children.Add($line)
    $RayLines += $line
}

$ParticleDots = @()
for ($index = 0; $index -lt 28; $index++) {
    $dot = New-Object Windows.Shapes.Ellipse
    $size = 1.2 + ($index % 5) * 0.55
    $dot.Width = $size
    $dot.Height = $size
    $dot.Fill = [Windows.Media.Brushes]::White
    $dot.Opacity = 0.0
    [void]$Particles.Children.Add($dot)
    $ParticleDots += $dot
}

$SurfaceBands = @()
for ($index = 0; $index -lt 6; $index++) {
    $band = New-Object Windows.Shapes.Ellipse
    $band.Fill = [Windows.Media.Brushes]::Transparent
    $band.StrokeThickness = 0.8 + ($index % 4) * 0.55
    $band.StrokeDashArray = New-Object Windows.Media.DoubleCollection
    foreach ($dash in @(1.0, (2.0 + $index % 3), (5.0 + $index % 5), 2.0)) { [void]$band.StrokeDashArray.Add($dash) }
    $band.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
    $band.RenderTransform = New-Object Windows.Media.RotateTransform
    $band.Opacity = 0.0
    [void]$Surface.Children.Add($band)
    $SurfaceBands += $band
}

$SurfaceDots = @()
$SurfaceSeeds = @()
for ($index = 0; $index -lt 14; $index++) {
    $spot = New-Object Windows.Shapes.Ellipse
    $size = 2.0 + $Random.NextDouble() * 6.0
    $spot.Width = $size
    $spot.Height = $size * (0.55 + $Random.NextDouble() * 0.45)
    $spot.Fill = [Windows.Media.Brushes]::White
    $spot.Opacity = 0.0
    [void]$Surface.Children.Add($spot)
    $SurfaceDots += $spot
    $SurfaceSeeds += [pscustomobject]@{
        radius = [Math]::Sqrt($Random.NextDouble())
        angle = $Random.NextDouble() * 2.0 * [Math]::PI
        speed = 0.10 + $Random.NextDouble() * 0.28
        phase = $Random.NextDouble() * 2.0 * [Math]::PI
    }
}

$ProminenceRings = @()
for ($index = 0; $index -lt 3; $index++) {
    $ring = New-Object Windows.Shapes.Ellipse
    $ring.Fill = [Windows.Media.Brushes]::Transparent
    $ring.StrokeThickness = 1.4 + ($index % 3) * 0.8
    $ring.StrokeDashArray = New-Object Windows.Media.DoubleCollection
    foreach ($dash in @(
        (2.0 + ($index % 4)),
        (3.0 + (($index + 1) % 5)),
        (8.0 + ($index % 3) * 2.0),
        4.0
    )) {
        [void]$ring.StrokeDashArray.Add($dash)
    }
    $ring.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
    $ring.RenderTransform = New-Object Windows.Media.RotateTransform
    $ring.Opacity = 0.0
    [void]$Prominences.Children.Add($ring)
    $ProminenceRings += $ring
}
$Random = $null

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
    [Windows.Controls.Canvas]::SetLeft($Element, $VisualCenterX - $Width / 2.0)
    [Windows.Controls.Canvas]::SetTop($Element, $VisualCenterY - $Height / 2.0)
}

function Get-Stage([double]$Level) {
    if ($Level -lt 0.15) { return "RED DWARF" }
    if ($Level -lt 0.35) { return "MAIN SEQUENCE" }
    if ($Level -lt 0.55) { return "BLUE GIANT" }
    if ($Level -lt 0.75) { return "HYPERGIANT" }
    if ($Level -lt 0.90) { return "NEUTRON STAR" }
    return "QUASAR"
}

function Get-EffectiveStage([double]$Level) {
    if ($script:StageMode -and $script:StageMode -ne "AUTO") {
        return [string]$script:StageMode
    }
    if ($State.stage) { return [string]$State.stage }
    return Get-Stage $Level
}

function Get-DisplayScale([double]$Level) {
    $manualScale = $script:StarScaleLevel / 3.0
    if (-not $script:GrowWithTokens) { return $manualScale }
    $safeLevel = [Math]::Min(1.0, [Math]::Max(0.0, $Level))
    return $manualScale * (0.65 + 0.35 * $safeLevel)
}

function Format-Mass([long]$Tokens) {
    if ($Tokens -ge 1000000) {
        return ($Tokens / 1000000.0).ToString(
            "0.00", [System.Globalization.CultureInfo]::InvariantCulture
        ) + "M"
    }
    return "{0:0}K" -f ($Tokens / 1000.0)
}

function New-CoronaGeometry([double]$Radius, [int]$Points, [double]$Phase, [double]$Turbulence) {
    $geometry = New-Object Windows.Media.StreamGeometry
    $context = $geometry.Open()
    try {
        for ($index = 0; $index -lt $Points; $index++) {
            $angle = 2.0 * [Math]::PI * $index / $Points
            $noise = 0.52 * [Math]::Sin($angle * 11.0 + $Phase) +
                     0.31 * [Math]::Sin($angle * 19.0 - $Phase * 1.7) +
                     0.17 * [Math]::Sin($angle * 31.0 + $Phase * 0.63)
            $cardinal = [Math]::Pow([Math]::Abs([Math]::Cos($angle * 2.0)), 18.0)
            $radiusAtPoint = $Radius * (1.0 + $Turbulence * $noise + $Turbulence * 1.7 * $cardinal)
            $pointX = $VisualCenterX + [Math]::Cos($angle) * $radiusAtPoint
            $pointY = $VisualCenterY + [Math]::Sin($angle) * $radiusAtPoint
            $point = New-Object Windows.Point($pointX, $pointY)
            if ($index -eq 0) { $context.BeginFigure($point, $true, $true) }
            else { $context.LineTo($point, $true, $false) }
        }
    }
    finally { $context.Dispose() }
    $geometry.Freeze()
    return $geometry
}

function Format-TokenDetail([long]$Tokens) {
    if ($Tokens -lt 0) { return "--" }
    return $Tokens.ToString("N0", [Globalization.CultureInfo]::CurrentCulture)
}

function Get-BreakdownToken($Breakdown, [string]$Name, [long]$Fallback = -1L) {
    if ($null -eq $Breakdown) { return $Fallback }
    $property = $Breakdown.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Fallback }
    try { return [long]$property.Value }
    catch { return $Fallback }
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

function Format-UiText([string]$Value, [string]$Fallback = "--") {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    $ascii = [regex]::Replace($Value, "[^\x20-\x7E]", " ")
    $clean = [regex]::Replace($ascii, "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return $Fallback }
    if ($clean.Length -gt 36) { return $clean.Substring(0, 33).TrimEnd() + "..." }
    return $clean
}

function Format-Effort([string]$Value) {
    $clean = Format-UiText $Value ""
    switch ($clean.ToLowerInvariant()) {
        "low" { return "Low" }
        "medium" { return "Medium" }
        "high" { return "High" }
        "xhigh" { return "Extra high" }
        "max" { return "Max" }
        "" { return "--" }
        default { return $clean }
    }
}

function Get-SessionSummary {
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$State.model)) {
        $model = Format-UiText ([string]$State.model)
        if ($model.Length -gt 18) { $model = $model.Substring(0, 15).TrimEnd() + "..." }
        $parts += $model
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.effort)) {
        $parts += (Format-Effort ([string]$State.effort))
    }
    return $parts -join " / "
}

function Get-DetailsText {
    $breakdown = $State.breakdown
    $limits = $State.rate_limits
    $model = Format-UiText ([string]$State.model)
    $effort = Format-Effort ([string]$State.effort)
    return @(
        "Model           $model"
        "Effort          $effort"
        "Active sessions $([Math]::Max(0, [int]$State.active_sessions))"
        ""
        "Total input     $(Format-TokenDetail (Get-BreakdownToken $breakdown 'total_input_tokens' 0L))"
        "Cache read      $(Format-TokenDetail (Get-BreakdownToken $breakdown 'cache_read_input_tokens' 0L))"
        "Remaining       $(Format-TokenDetail (Get-BreakdownToken $breakdown 'remaining_tokens' 0L))"
        ""
        "5-hour limit    $(if ([double]$limits.five_hour.used_percentage -ge 0) { '%' + [Math]::Round([double]$limits.five_hour.used_percentage) } else { '--' })"
        "Reset in        $(Format-ResetRemaining ([long]$limits.five_hour.resets_at))"
        "7-day limit     $(if ([double]$limits.seven_day.used_percentage -ge 0) { '%' + [Math]::Round([double]$limits.seven_day.used_percentage) } else { '--' })"
    ) -join "`n"
}

$EmptyBreakdown = [pscustomobject]@{ total_input_tokens = 0L; cache_read_input_tokens = 0L; context_window_size = 0L; remaining_tokens = 0L }
$EmptyRateLimits = [pscustomobject]@{ five_hour = [pscustomobject]@{ used_percentage = -1.0; resets_at = 0L }; seven_day = [pscustomobject]@{ used_percentage = -1.0; resets_at = 0L } }
$State = [pscustomobject]@{ level = 0.0; tokens = 0L; active = $false; stage = "RED DWARF"; project_root = ""; project_name = ""; model = ""; effort = ""; active_sessions = 0; breakdown = $EmptyBreakdown; rate_limits = $EmptyRateLimits }
$LastStateWrite = [datetime]::MinValue
$OverlayPosition = [pscustomobject]@{ x = 0.96; y = 0.06 }
$LastHostWindow = $null
$LastHostSignature = ""
$LastMassLayoutKey = ""
$LastDetailsText = ""
$StarScaleLevel = 3
$PositionLocked = $false
$ValidStageModes = @("AUTO", "RED DWARF", "MAIN SEQUENCE", "BLUE GIANT", "HYPERGIANT", "NEUTRON STAR", "QUASAR")
$StageMode = "AUTO"
$GrowWithTokens = $false
$LastAppliedDisplayScale = -1.0
$NextStatePoll = 0.0
$CachedForegroundHandle = [IntPtr]::Zero
$CachedHostWindow = $null
$NextHostRefresh = 0.0
$NextCoronaUpdate = 0.0
$NextUiRefresh = 0.0
$NextVisibilityPoll = 0.0
$NextControlPoll = 0.0
$OverlayVisible = $false
$LastRenderedStage = ""
$LastDragSize = -1.0
$WorkingSetTrimmed = $false
$AllowedIdeProcesses = @("pycharm64", "pycharm", "idea64", "idea", "webstorm64", "webstorm", "rider64", "rider", "clion64", "clion", "goland64", "goland", "phpstorm64", "phpstorm", "rubymine64", "rubymine", "datagrip64", "datagrip", "studio64", "studio", "code", "cursor", "devenv", "eclipse")
$StageColors = @{
    "RED DWARF" = @("#FFFF7A32", "#FF6D0702", "#001D0000")
    "MAIN SEQUENCE" = @("#FFFFE89A", "#FFD95A09", "#002E0900")
    "BLUE GIANT" = @("#FFE9F7FF", "#FF2768C7", "#000B2D88")
    "HYPERGIANT" = @("#FFFFFFD8", "#FFFF8E18", "#003F0B00")
    "NEUTRON STAR" = @("#FFFFFFFF", "#FF2B78D4", "#00042A88")
    "QUASAR" = @("#FF000000", "#FF000000", "#00000000")
}
$SurfaceAccentColors = @{
    "RED DWARF" = "#CC3B0000"
    "MAIN SEQUENCE" = "#CCFF8A16"
    "BLUE GIANT" = "#CC4B8EE8"
    "HYPERGIANT" = "#CCFF9A14"
    "NEUTRON STAR" = "#CC4F9EFF"
}
$QuasarTilt = -12.0 * [Math]::PI / 180.0
$QuasarTiltCos = [Math]::Cos($QuasarTilt)
$QuasarTiltSin = [Math]::Sin($QuasarTilt)
$QuasarAxis = -102.0 * [Math]::PI / 180.0
$QuasarAxisCos = [Math]::Cos($QuasarAxis)
$QuasarAxisSin = [Math]::Sin($QuasarAxis)

if (Test-Path -LiteralPath $PositionPath) {
    try {
        $savedPosition = [IO.File]::ReadAllText($PositionPath) | ConvertFrom-Json
        $savedX = [double]$savedPosition.x
        $savedY = [double]$savedPosition.y
        if ([double]::IsNaN($savedX) -or [double]::IsInfinity($savedX)) { $savedX = 0.96 }
        if ([double]::IsNaN($savedY) -or [double]::IsInfinity($savedY)) { $savedY = 0.06 }
        $OverlayPosition = [pscustomobject]@{
            x = [Math]::Min(1.0, [Math]::Max(0.0, $savedX))
            y = [Math]::Min(1.0, [Math]::Max(0.0, $savedY))
        }
        if ($savedPosition.PSObject.Properties['scale']) {
            $savedScale = [int]$savedPosition.scale
            if ($savedScale -ge 1 -and $savedScale -le 3) { $StarScaleLevel = $savedScale }
        }
        if ($savedPosition.PSObject.Properties['locked']) {
            $PositionLocked = [bool]$savedPosition.locked
        }
        if ($savedPosition.PSObject.Properties['stage_mode']) {
            $savedStageMode = ([string]$savedPosition.stage_mode).ToUpperInvariant()
            if ($ValidStageModes -contains $savedStageMode) { $StageMode = $savedStageMode }
        }
        if ($savedPosition.PSObject.Properties['grow_with_tokens']) {
            $GrowWithTokens = [bool]$savedPosition.grow_with_tokens
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
            model = "Opus 5"
            effort = "xhigh"
            active_sessions = 2
            breakdown = [pscustomobject]@{ total_input_tokens = $demoTokens; cache_read_input_tokens = [long][Math]::Round($demoTokens * 0.70); context_window_size = 200000L; remaining_tokens = 200000L - $demoTokens }
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
            model = [string]$value.model
            effort = [string]$value.effort
            active_sessions = if ($value.PSObject.Properties['active_sessions']) { [Math]::Max(0, [int]$value.active_sessions) } elseif ([bool]$value.active) { 1 } else { 0 }
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
    $script:NextHostRefresh = $now + 1.0
    $processId = [uint32]0
    [void][TokenStarNative]::GetWindowThreadProcessId($handle, [ref]$processId)
    try { $process = Get-Process -Id $processId -ErrorAction Stop }
    catch { $script:CachedHostWindow = $null; return $null }
    if (-not $Demo -and $script:AllowedIdeProcesses -notcontains $process.ProcessName) {
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
$LockPositionCheckBox.IsChecked = $PositionLocked

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

function Get-PlacementInset {
    $baseInset = switch (Get-EffectiveStage ([double]$State.level)) {
        "RED DWARF" { 38.0 }
        "MAIN SEQUENCE" { 50.0 }
        "BLUE GIANT" { 64.0 }
        "HYPERGIANT" { 78.0 }
        "NEUTRON STAR" { 38.0 }
        default { 52.0 }
    }
    return [Math]::Max(8.0, $baseInset * (Get-DisplayScale ([double]$State.level)) * 0.25)
}

function Get-WindowTravelBounds($HostWindow) {
    $scale = Get-OverlayScale ([double]$HostWindow.Scale)
    $margin = 1.0
    $left = $HostWindow.Rect.Left / $scale + $margin
    $top = $HostWindow.Rect.Top / $scale + $margin
    $right = $HostWindow.Rect.Right / $scale - $margin
    $bottom = $HostWindow.Rect.Bottom / $scale - $margin
    $inset = Get-PlacementInset
    $minLeft = $left + $inset - $CenterX
    $maxLeft = [Math]::Max($minLeft, $right - $inset - $CenterX)
    $minTop = $top + $inset - $CenterY
    $maxTop = [Math]::Max($minTop, $bottom - $inset - $CenterY)
    return [pscustomobject]@{
        MinLeft = $minLeft
        MaxLeft = $maxLeft
        MinTop = $minTop
        MaxTop = $maxTop
        Width = $maxLeft - $minLeft
        Height = $maxTop - $minTop
        HostLeft = $left
        HostTop = $top
        HostRight = $right
        HostBottom = $bottom
    }
}

function Update-RootClip($Bounds) {
    $clipLeft = [Math]::Max(0.0, $Bounds.HostLeft - $Window.Left)
    $clipTop = [Math]::Max(0.0, $Bounds.HostTop - $Window.Top)
    $clipRight = [Math]::Min($Window.Width, $Bounds.HostRight - $Window.Left)
    $clipBottom = [Math]::Min($Window.Height, $Bounds.HostBottom - $Window.Top)
    $clipWidth = [Math]::Max(0.0, $clipRight - $clipLeft)
    $clipHeight = [Math]::Max(0.0, $clipBottom - $clipTop)
    if (-not $script:RootClipGeometry) {
        $script:RootClipGeometry = [Windows.Media.RectangleGeometry]::new()
        $Root.Clip = $script:RootClipGeometry
    }
    $script:RootClipGeometry.Rect = [Windows.Rect]::new($clipLeft, $clipTop, $clipWidth, $clipHeight)
}

function Set-WindowFootprint([double]$RequiredBottom) {
    $targetHeight = [Math]::Ceiling([Math]::Min(1200.0, [Math]::Max(540.0, $RequiredBottom)))
    if ([Math]::Abs([double]$Window.Height - $targetHeight) -lt 0.5) { return }
    $Window.Height = $targetHeight
    $Root.Height = $targetHeight
    $script:CanvasHeight = $targetHeight
    if ($script:LastHostWindow -and $script:LastHostWindow.Rect) {
        Update-RootClip (Get-WindowTravelBounds $script:LastHostWindow)
    }
}

function Set-WindowPosition($HostWindow) {
    if (-not $HostWindow -or -not $HostWindow.Rect) { return }
    $bounds = Get-WindowTravelBounds $HostWindow
    $Window.Left = $bounds.MinLeft + $bounds.Width * [double]$OverlayPosition.x
    $Window.Top = $bounds.MinTop + $bounds.Height * [double]$OverlayPosition.y
    Update-RootClip $bounds
}

function Set-DraggedWindowPosition([double]$Left, [double]$Top, $HostWindow) {
    if (-not $HostWindow -or -not $HostWindow.Rect) { return }
    $bounds = Get-WindowTravelBounds $HostWindow
    $Window.Left = [Math]::Min($bounds.MaxLeft, [Math]::Max($bounds.MinLeft, $Left))
    $Window.Top = [Math]::Min($bounds.MaxTop, [Math]::Max($bounds.MinTop, $Top))
    Update-RootClip $bounds
}

function Save-WindowPosition {
    $hostWindow = if ($script:LastHostWindow) { $script:LastHostWindow } else { Get-IdeWindow }
    $savedX = [double]$script:OverlayPosition.x
    $savedY = [double]$script:OverlayPosition.y
    $windowLeft = [double]$Window.Left
    $windowTop = [double]$Window.Top
    if ($hostWindow -and $hostWindow.Rect -and
        -not [double]::IsNaN($windowLeft) -and -not [double]::IsInfinity($windowLeft) -and
        -not [double]::IsNaN($windowTop) -and -not [double]::IsInfinity($windowTop)) {
        $bounds = Get-WindowTravelBounds $hostWindow
        $clampedLeft = [Math]::Min($bounds.MaxLeft, [Math]::Max($bounds.MinLeft, $windowLeft))
        $clampedTop = [Math]::Min($bounds.MaxTop, [Math]::Max($bounds.MinTop, $windowTop))
        $Window.Left = $clampedLeft
        $Window.Top = $clampedTop
        $savedX = if ($bounds.Width -gt 0) { ($clampedLeft - $bounds.MinLeft) / $bounds.Width } else { 0.0 }
        $savedY = if ($bounds.Height -gt 0) { ($clampedTop - $bounds.MinTop) / $bounds.Height } else { 0.0 }
        Update-RootClip $bounds
    }
    if ([double]::IsNaN($savedX) -or [double]::IsInfinity($savedX)) { $savedX = 0.96 }
    if ([double]::IsNaN($savedY) -or [double]::IsInfinity($savedY)) { $savedY = 0.06 }
    $script:OverlayPosition = [pscustomobject]@{
        x = [Math]::Min(1.0, [Math]::Max(0.0, $savedX))
        y = [Math]::Min(1.0, [Math]::Max(0.0, $savedY))
        scale = $script:StarScaleLevel
        locked = $script:PositionLocked
        stage_mode = $script:StageMode
        grow_with_tokens = $script:GrowWithTokens
    }
    $json = ($script:OverlayPosition | ConvertTo-Json -Compress) + "`n"
    $temporary = $PositionPath + ".tmp"
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $PositionPath -Force
}

$OverlayHandle = [IntPtr]::Zero
$DragHandleActive = $false
$InteractivePanelActive = $false
$ClickThroughEnabled = $true
$DetailsOpen = $false
$IsDragging = $false
$DragStartCursorX = 0.0
$DragStartCursorY = 0.0
$DragStartWindowLeft = 0.0
$DragStartWindowTop = 0.0
$DragDpiScale = 1.0
$DownArrow = [string][char]0x25BC
$UpArrow = [string][char]0x25B2
$DefaultPanelBorder = New-Object Windows.Media.SolidColorBrush((Convert-Color "#CC5F91BF"))
$HoverPanelBorder = New-Object Windows.Media.SolidColorBrush((Convert-Color "#FFFFFFFF"))
$ScaleButtonInactive = New-Object Windows.Media.SolidColorBrush((Convert-Color "#FF0D1A27"))
$ScaleButtonActive = New-Object Windows.Media.SolidColorBrush((Convert-Color "#FF28577D"))
foreach ($brush in @($DefaultPanelBorder, $HoverPanelBorder, $ScaleButtonInactive, $ScaleButtonActive)) { $brush.Freeze() }

function Set-VisualGroupVisibility($Elements, [bool]$Visible) {
    $visibility = if ($Visible) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    foreach ($element in $Elements) { $element.Visibility = $visibility }
}

function Set-StageVisualVisibility([string]$Stage) {
    if ($Stage -eq $script:LastRenderedStage) { return }
    $script:LastRenderedStage = $Stage
    $normal = $Stage -in @("RED DWARF", "MAIN SEQUENCE", "BLUE GIANT", "HYPERGIANT")
    $neutron = $Stage -eq "NEUTRON STAR"
    $quasar = $Stage -eq "QUASAR"

    Set-VisualGroupVisibility @($PulseRingOuter, $PulseRingInner, $Rays, $HaloOuter, $HaloInner, $CoronaShellOuter, $CoronaShellInner, $Surface) $normal
    Set-VisualGroupVisibility @($Nebula, $Glow, $Core, $Prominences) ($normal -or $neutron)
    Set-VisualGroupVisibility @($NeutronBeamAura, $NeutronBeamGlow, $NeutronBeam, $NeutronBeamHot) $neutron
    Set-VisualGroupVisibility @($JetAura, $JetGlow, $JetCore, $DiskAura, $DiskOuter, $DiskGlow, $Disk, $DiskHot, $BlackCore, $DiskFrontGlow, $DiskFront) $quasar
    $script:LastMassLayoutKey = ""
}

function Apply-StarScale([double]$Level = 0.0) {
    $multiplier = Get-DisplayScale $Level
    if ([Math]::Abs($multiplier - $script:LastAppliedDisplayScale) -gt 0.000001) {
        $VisualLayer.RenderTransform = [Windows.Media.ScaleTransform]::new($multiplier, $multiplier, $VisualCenterX, $VisualCenterY)
        $script:LastAppliedDisplayScale = $multiplier
    }
    foreach ($entry in @(
        [pscustomobject]@{ Level = 1; Button = $Scale1Button },
        [pscustomobject]@{ Level = 2; Button = $Scale2Button },
        [pscustomobject]@{ Level = 3; Button = $Scale3Button }
    )) {
        $entry.Button.Background = if ($entry.Level -eq $script:StarScaleLevel) { $ScaleButtonActive } else { $ScaleButtonInactive }
        $entry.Button.FontWeight = if ($entry.Level -eq $script:StarScaleLevel) { "Bold" } else { "Normal" }
    }
}

function Set-StarScale([int]$Level) {
    if ($Level -lt 1 -or $Level -gt 3) { return }
    $script:StarScaleLevel = $Level
    Apply-StarScale ([double]$State.level)
    $script:LastMassLayoutKey = ""
    Update-Visual
    if ($script:LastHostWindow -and $script:LastHostWindow.Rect) {
        Set-WindowPosition $script:LastHostWindow
        Save-WindowPosition
    }
}

function Set-StageMode([string]$Mode, [bool]$Persist = $true) {
    $normalized = $Mode.ToUpperInvariant()
    if ($script:ValidStageModes -notcontains $normalized) { return }
    $script:StageMode = $normalized
    foreach ($item in @($StageModeComboBox.Items)) {
        if ([string]$item.Tag -eq $normalized -and $StageModeComboBox.SelectedItem -ne $item) {
            $StageModeComboBox.SelectedItem = $item
            break
        }
    }
    $script:LastMassLayoutKey = ""
    Update-Visual
    if ($script:LastHostWindow -and $script:LastHostWindow.Rect) {
        Set-WindowPosition $script:LastHostWindow
    }
    if ($Persist -and -not $SelfTest) { Save-WindowPosition }
}

function Set-GrowWithTokens([bool]$Enabled, [bool]$Persist = $true) {
    $script:GrowWithTokens = $Enabled
    if ([bool]$GrowWithTokensCheckBox.IsChecked -ne $Enabled) {
        $GrowWithTokensCheckBox.IsChecked = $Enabled
    }
    $script:LastAppliedDisplayScale = -1.0
    Apply-StarScale ([double]$State.level)
    $script:LastMassLayoutKey = ""
    Update-Visual
    if ($script:LastHostWindow -and $script:LastHostWindow.Rect) {
        Set-WindowPosition $script:LastHostWindow
    }
    if ($Persist -and -not $SelfTest) { Save-WindowPosition }
}

function Set-PositionLock([bool]$Locked, [bool]$Persist = $true) {
    $script:PositionLocked = $Locked
    $DragHandle.Cursor = if ($Locked) { "Arrow" } else { "SizeAll" }
    $DragHandle.ToolTip = if ($Locked) { "Position locked. Unlock it from the details menu to move the star." } else { "Drag the token star" }
    if ($Persist) { Save-WindowPosition }
}

foreach ($item in @($StageModeComboBox.Items)) {
    if ([string]$item.Tag -eq $StageMode) {
        $StageModeComboBox.SelectedItem = $item
        break
    }
}
$GrowWithTokensCheckBox.IsChecked = $GrowWithTokens
$LockPositionCheckBox.IsChecked = $PositionLocked
Apply-StarScale ([double]$State.level)

function Test-PointOverElement($Point, $Element, [double]$Padding = 0.0) {
    $left = [Windows.Controls.Canvas]::GetLeft($Element)
    $top = [Windows.Controls.Canvas]::GetTop($Element)
    if ([double]::IsNaN($left)) { $left = 0.0 }
    if ([double]::IsNaN($top)) { $top = 0.0 }
    $width = [double]$Element.ActualWidth
    $height = [double]$Element.ActualHeight
    if ($width -le 0.0 -or [double]::IsNaN($width)) { $width = [double]$Element.DesiredSize.Width }
    if ($height -le 0.0 -or [double]::IsNaN($height)) { $height = [double]$Element.DesiredSize.Height }
    $explicitWidth = [double]$Element.Width
    $explicitHeight = [double]$Element.Height
    if (-not [double]::IsNaN($explicitWidth)) { $width = [Math]::Max($width, $explicitWidth) }
    if (-not [double]::IsNaN($explicitHeight)) { $height = [Math]::Max($height, $explicitHeight) }
    return $Point.X -ge ($left - $Padding) -and $Point.X -le ($left + $width + $Padding) -and
           $Point.Y -ge ($top - $Padding) -and $Point.Y -le ($top + $height + $Padding)
}

function Get-CursorHitMask {
    $point = New-Object TokenStarNative+POINT
    if ($Window.Opacity -le 0.01 -or -not [TokenStarNative]::GetCursorPos([ref]$point)) {
        return 0
    }
    try {
        if ($script:LastHostWindow -and $script:LastHostWindow.Rect -and
            ($point.X -lt $script:LastHostWindow.Rect.Left -or $point.X -gt $script:LastHostWindow.Rect.Right -or
             $point.Y -lt $script:LastHostWindow.Rect.Top -or $point.Y -gt $script:LastHostWindow.Rect.Bottom)) {
            return 0
        }
        $local = $Window.PointFromScreen([Windows.Point]::new($point.X, $point.Y))
        $mask = 0
        if (Test-PointOverElement $local $DragHandle 7.0) { $mask = $mask -bor 1 }
        if (Test-PointOverElement $local $MassPanel 9.0) { $mask = $mask -bor 2 }
        if ($script:DetailsOpen -and (Test-PointOverElement $local $DetailsPanel 4.0)) { $mask = $mask -bor 4 }
        return $mask
    }
    catch { return 0 }
}

function Update-HitTestMode {
    if ($script:OverlayHandle -eq [IntPtr]::Zero) { return }
    $hit = Get-CursorHitMask
    $overStar = ($hit -band 1) -ne 0
    $overPanel = ($hit -band 2) -ne 0
    $overDetails = ($hit -band 4) -ne 0

    $script:DragHandleActive = $overStar
    $script:InteractivePanelActive = $overPanel
    $MassPanel.BorderBrush = if ($overPanel) { $HoverPanelBorder } else { $DefaultPanelBorder }
    if ($Window.Opacity -gt 0.01) {
        $MassPanel.Opacity = if ($overPanel) { 0.96 } else { 0.46 }
    }
    $shouldClickThrough = -not ($overStar -or $overPanel -or $overDetails)
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

function Complete-StarDrag {
    if (-not $script:IsDragging) { return }
    $script:IsDragging = $false
    [Windows.Input.Mouse]::Capture($null) | Out-Null
    Save-WindowPosition
    $script:LastMassLayoutKey = ""
    $VisualLayer.CacheMode = $null
    Update-Visual
    if ($script:Timer) { $script:Timer.Start() }
    if ($script:LastHostWindow -and $script:LastHostWindow.Handle) {
        [void][TokenStarNative]::SetForegroundWindow($script:LastHostWindow.Handle)
    }
}

$DragHandle.Add_PreviewMouseLeftButtonDown({
    if ($_.ChangedButton -ne [Windows.Input.MouseButton]::Left) { return }
    if ($script:PositionLocked) {
        $_.Handled = $true
        return
    }
    $cursor = New-Object TokenStarNative+POINT
    if (-not [TokenStarNative]::GetCursorPos([ref]$cursor)) { return }
    $script:IsDragging = $true
    $script:DragStartCursorX = [double]$cursor.X
    $script:DragStartCursorY = [double]$cursor.Y
    $script:DragStartWindowLeft = [double]$Window.Left
    $script:DragStartWindowTop = [double]$Window.Top
    $script:DragDpiScale = Get-OverlayScale $(if ($script:LastHostWindow) { [double]$script:LastHostWindow.Scale } else { 1.0 })
    if ($script:DragDpiScale -le 0.0) { $script:DragDpiScale = 1.0 }
    if ($script:Timer) { $script:Timer.Stop() }
    $VisualLayer.CacheMode = New-Object Windows.Media.BitmapCache
    [Windows.Input.Mouse]::Capture($DragHandle) | Out-Null
    $_.Handled = $true
})

$DragHandle.Add_PreviewMouseMove({
    if (-not $script:IsDragging) { return }
    if ([Windows.Input.Mouse]::LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) {
        Complete-StarDrag
        return
    }
    $cursor = New-Object TokenStarNative+POINT
    if (-not [TokenStarNative]::GetCursorPos([ref]$cursor)) { return }
    $left = $script:DragStartWindowLeft + ([double]$cursor.X - $script:DragStartCursorX) / $script:DragDpiScale
    $top = $script:DragStartWindowTop + ([double]$cursor.Y - $script:DragStartCursorY) / $script:DragDpiScale
    Set-DraggedWindowPosition $left $top $script:LastHostWindow
    $_.Handled = $true
})

$DragHandle.Add_PreviewMouseLeftButtonUp({
    if ($script:IsDragging) {
        Complete-StarDrag
        $_.Handled = $true
    }
})

$DragHandle.Add_LostMouseCapture({
    if ($script:IsDragging -and [Windows.Input.Mouse]::LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) {
        Complete-StarDrag
    }
})

function Toggle-DetailsPanel {
    $script:DetailsOpen = -not $script:DetailsOpen
    $DetailsButton.Content = if ($script:DetailsOpen) { $script:UpArrow } else { $script:DownArrow }
    $DetailsPanel.Visibility = if ($script:DetailsOpen) { "Visible" } else { "Collapsed" }
    $DetailsPanel.Opacity = if ($script:DetailsOpen) { 1.0 } else { 0.0 }
    $MassPanel.Opacity = if ($script:InteractivePanelActive) { 0.96 } else { 0.46 }
    $script:LastMassLayoutKey = ""
    Update-Visual
    if ($script:LastHostWindow -and $script:LastHostWindow.Handle) {
        [void][TokenStarNative]::SetForegroundWindow($script:LastHostWindow.Handle)
    }
}

$DetailsButton.Add_Click({
    Toggle-DetailsPanel
    $_.Handled = $true
})

$Scale1Button.Add_Click({ Set-StarScale 1; $_.Handled = $true })
$Scale2Button.Add_Click({ Set-StarScale 2; $_.Handled = $true })
$Scale3Button.Add_Click({ Set-StarScale 3; $_.Handled = $true })
$StageModeComboBox.Add_SelectionChanged({
    if ($StageModeComboBox.SelectedItem -and $StageModeComboBox.SelectedItem.Tag) {
        Set-StageMode ([string]$StageModeComboBox.SelectedItem.Tag)
    }
    $_.Handled = $true
})
$GrowWithTokensCheckBox.Add_Checked({ Set-GrowWithTokens $true; $_.Handled = $true })
$GrowWithTokensCheckBox.Add_Unchecked({ Set-GrowWithTokens $false; $_.Handled = $true })
$LockPositionCheckBox.Add_Checked({ Set-PositionLock $true; $_.Handled = $true })
$LockPositionCheckBox.Add_Unchecked({ Set-PositionLock $false; $_.Handled = $true })
Set-PositionLock $PositionLocked $false

$Stopwatch = [Diagnostics.Stopwatch]::StartNew()
function Update-Visual {
    $time = $Stopwatch.Elapsed.TotalSeconds
    if (-not $SelfTest -and $time -ge $script:NextControlPoll) {
        $script:NextControlPoll = $time + 1.0
        if (Test-Path -LiteralPath $StopPath) {
            $Window.Close()
            return
        }
    }
    if (-not $script:WorkingSetTrimmed -and $time -ge 4.0) {
        $script:WorkingSetTrimmed = $true
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        try { [void][TokenStarNative]::EmptyWorkingSet(([Diagnostics.Process]::GetCurrentProcess()).Handle) }
        catch { }
    }
    if ($time -ge $script:NextStatePoll) {
        Read-TokenState
        $script:NextStatePoll = $time + 1.0
    }
    $level = [double]$State.level
    $stage = Get-EffectiveStage $level
    Apply-StarScale $level

    $hostWindow = $script:LastHostWindow
    $visible = [bool]$script:OverlayVisible
    if ($SelfTest -or $time -ge $script:NextVisibilityPoll) {
        $script:NextVisibilityPoll = $time + 1.0
        $hostWindow = if ($SelfTest) { [pscustomobject]@{ Rect = $null; Scale = 1.0; Title = "" } } else { Get-IdeWindow }
        $visible = [bool]$State.active -and $null -ne $hostWindow -and (Test-ProjectWindow $hostWindow)
        $script:OverlayVisible = $visible
        $Window.Opacity = if ($visible -or $SelfTest) { 1.0 } else { 0.0 }
        $DragHandle.IsHitTestVisible = $visible -or $SelfTest
        $MassPanel.IsHitTestVisible = $visible -or $SelfTest
        $DetailsPanel.IsHitTestVisible = ($visible -or $SelfTest) -and $script:DetailsOpen
        if ($script:Timer) {
            $targetInterval = if (-not $visible) { 1500 } elseif ($stage -in @("RED DWARF", "MAIN SEQUENCE", "BLUE GIANT", "HYPERGIANT")) { 400 } else { 300 }
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
    }
    if (-not $visible -and -not $SelfTest) { return }

    $isNormal = $stage -in @("RED DWARF", "MAIN SEQUENCE", "BLUE GIANT", "HYPERGIANT")
    $isHyper = $stage -eq "HYPERGIANT"
    $isNeutron = $stage -eq "NEUTRON STAR"
    $isQuasar = $stage -eq "QUASAR"
    $stageChanged = $stage -ne $script:LastRenderedStage
    Set-StageVisualVisibility $stage

    $diameter = switch ($stage) {
        "RED DWARF" { 68.0 }
        "MAIN SEQUENCE" { 96.0 }
        "BLUE GIANT" { 128.0 }
        "HYPERGIANT" { 158.0 }
        "NEUTRON STAR" { 42.0 }
        default { 92.0 }
    }
    $starMultiplier = Get-DisplayScale $level
    $displayDiameter = $diameter * $starMultiplier
    $dragSize = [Math]::Max(28.0, $displayDiameter)
    if ([Math]::Abs($dragSize - $script:LastDragSize) -gt 0.01) {
        $script:LastDragSize = $dragSize
        $DragHandle.Width = $dragSize
        $DragHandle.Height = $dragSize
        [Windows.Controls.Canvas]::SetLeft($DragHandle, $CenterX - $dragSize / 2.0)
        [Windows.Controls.Canvas]::SetTop($DragHandle, $CenterY - $dragSize / 2.0)
    }
    $colors = $script:StageColors[$stage]
    $stageBrush = Get-SolidBrush $colors[0]
    $NeutronAngle = 0.0

    if ($isNormal -or $isNeutron) {
        if ($stageChanged) {
            $glowDiameter = $diameter * $(if ($isNeutron) { 4.8 } else { 2.75 })
            Set-CenteredSize $Glow $glowDiameter $glowDiameter
            Set-CenteredSize $Core $diameter $diameter
            $Core.Fill = Get-RadialBrush $colors[0] $colors[1]
            $Core.Stroke = Get-SolidBrush $(if ($isNeutron) { "#FFFFFFFF" } else { $colors[0] })
            $Core.StrokeThickness = if ($isNeutron) { 3.0 } else { 0.0 }
            $Glow.Fill = Get-RadialBrush $colors[0] $colors[2]
            $nebulaDiameter = $diameter * $(if ($isNeutron) { 6.8 } else { 4.2 })
            Set-CenteredSize $Nebula $nebulaDiameter $nebulaDiameter
            $Nebula.Fill = Get-RadialBrush $colors[0] $colors[2]
        }
        $Core.Opacity = 1.0
        $Glow.Opacity = if ($isNormal) { 0.76 } else { 0.96 }
        $Nebula.Opacity = if ($isNormal) { 0.28 + 0.12 * [Math]::Sin($time * 1.7) } else { 0.42 }
    }

    if ($isNormal -and $time -ge $script:NextCoronaUpdate) {
        $script:NextCoronaUpdate = $time + 1.5
        $coreRadius = $diameter / 2.0
        $CoronaShellOuter.Data = New-CoronaGeometry ($coreRadius * 2.18) 28 ($time * 0.72) (0.18 + 0.10 * $level)
        $CoronaShellInner.Data = New-CoronaGeometry ($coreRadius * 1.48) 28 (-$time * 1.08) (0.13 + 0.08 * $level)
        $CoronaShellOuter.Fill = Get-RadialBrush $colors[0] $colors[2]
        $CoronaShellInner.Fill = Get-RadialBrush $colors[0] $colors[2]
        $CoronaShellOuter.Stroke = Get-SolidBrush $colors[0]
        $CoronaShellInner.Stroke = Get-SolidBrush $colors[0]
        $CoronaShellOuter.StrokeThickness = 0.7
        $CoronaShellInner.StrokeThickness = 1.1
        $CoronaShellOuter.Opacity = 0.24 + 0.16 * $level
        $CoronaShellInner.Opacity = 0.38 + 0.22 * $level
    }
    if ($isNormal) {
        $pulse = 0.5 + 0.5 * [Math]::Sin($time * 2.6)
        Set-CenteredSize $PulseRingInner ($diameter * (1.30 + 0.12 * $pulse)) ($diameter * (1.30 + 0.12 * $pulse))
        Set-CenteredSize $PulseRingOuter ($diameter * (1.72 + 0.20 * $pulse)) ($diameter * (1.72 + 0.20 * $pulse))
        $PulseRingInner.Stroke = $stageBrush
        $PulseRingOuter.Stroke = $stageBrush
        $PulseRingInner.Opacity = (0.30 + 0.24 * $level) * (1.0 - $pulse)
        $PulseRingOuter.Opacity = (0.18 + 0.22 * $level) * $pulse
        $surfaceAccent = Get-SolidBrush $script:SurfaceAccentColors[$stage]

        for ($index = 0; $index -lt $SurfaceBands.Count; $index++) {
            $band = $SurfaceBands[$index]
            $bandWidth = $diameter * (0.25 + $index * 0.039)
            $bandHeight = $bandWidth * (0.18 + 0.055 * ($index % 5))
            if ($stageChanged) { Set-CenteredSize $band $bandWidth $bandHeight }
            $band.Stroke = if ($index % 4 -eq 0) { [Windows.Media.Brushes]::White } elseif ($index % 3 -eq 0) { $surfaceAccent } else { $stageBrush }
            $band.RenderTransform.Angle = ($index * 41.0 + $time * $(if ($index % 2 -eq 0) { 13.0 } else { -9.0 })) % 360.0
            $band.StrokeDashOffset = $time * $(if ($index % 2 -eq 0) { 7.0 } else { -5.0 }) + $index
            $band.Opacity = 0.11 + 0.025 * ($index % 6)
        }

        $rayRadius = $diameter * 0.52
        for ($index = 0; $index -lt $RayLines.Count; $index++) {
            $angle = $index * (360.0 / $RayLines.Count) + $time * (8.0 + $level * 18.0)
            $radians = $angle * [Math]::PI / 180.0
            $inner = $rayRadius * 0.84
            $flareGain = if ($index % 12 -eq 0) { 3.8 + 1.3 * $level } elseif ($index % 4 -eq 0) { 2.0 + 0.8 * $level } else { 1.25 + 0.75 * $level }
            $outer = $rayRadius * ($flareGain + 0.42 * [Math]::Sin($time * 2.1 + $index * 1.7))
            $line = $RayLines[$index]
            $line.X1 = $VisualCenterX + [Math]::Cos($radians) * $inner
            $line.Y1 = $VisualCenterY + [Math]::Sin($radians) * $inner
            $line.X2 = $VisualCenterX + [Math]::Cos($radians) * $outer
            $line.Y2 = $VisualCenterY + [Math]::Sin($radians) * $outer
            $line.Stroke = $stageBrush
            $line.Opacity = if ($index % 12 -eq 0) { 0.68 } elseif ($index % 4 -eq 0) { 0.46 } else { 0.22 + 0.30 * $level }
        }

        for ($index = 0; $index -lt $SurfaceDots.Count; $index++) {
            $spot = $SurfaceDots[$index]
            $seed = $SurfaceSeeds[$index]
            $angle = [double]$seed.angle + $time * [double]$seed.speed
            $radius = $diameter * 0.43 * [double]$seed.radius
            [Windows.Controls.Canvas]::SetLeft($spot, $VisualCenterX + [Math]::Cos($angle) * $radius - $spot.Width / 2.0)
            [Windows.Controls.Canvas]::SetTop($spot, $VisualCenterY + [Math]::Sin($angle) * $radius - $spot.Height / 2.0)
            $spot.Fill = if ($index % 7 -eq 0) { [Windows.Media.Brushes]::White } elseif ($index % 3 -eq 0) { $surfaceAccent } else { $stageBrush }
            $spot.Opacity = 0.07 + 0.24 * (0.5 + 0.5 * [Math]::Sin($time * 1.7 + [double]$seed.phase))
        }

        if ($stageChanged) {
            Set-CenteredSize $HaloInner ($diameter * 1.42) ($diameter * 1.42)
            Set-CenteredSize $HaloOuter ($diameter * 1.85) ($diameter * 1.85)
        }
        $HaloInner.Opacity = if ($isHyper) { 0.88 } else { 0.0 }
        $HaloOuter.Opacity = if ($isHyper) { 0.62 } else { 0.0 }
    }

    if ($isNormal -or $isNeutron) {
        for ($index = 0; $index -lt $ProminenceRings.Count; $index++) {
            $ring = $ProminenceRings[$index]
            if ($isNormal) {
            $ringWidth = $diameter * (1.16 + $index * 0.10)
            $ringHeight = $ringWidth * (0.54 + 0.055 * ($index % 4))
            if ($stageChanged) { Set-CenteredSize $ring $ringWidth $ringHeight }
            $ring.Stroke = $stageBrush
            $ring.RenderTransform.Angle = ($index * 37.0 + $time * $(if ($index % 2 -eq 0) { 9.0 } else { -6.0 })) % 360.0
            $ring.StrokeDashOffset = $time * $(if ($index % 2 -eq 0) { 3.5 } else { -2.8 })
            $ring.Opacity = 0.16 + 0.055 * $index + $(if ($isHyper) { 0.18 } else { 0.0 })
            }
            else {
            $ringWidth = 102.0 + $index * 15.0
            $ringHeight = 32.0 + ($index % 4) * 13.0
            if ($stageChanged) { Set-CenteredSize $ring $ringWidth $ringHeight }
            $ring.Stroke = Get-SolidBrush $(if ($index % 3 -eq 0) { "#FFD9FAFF" } elseif ($index % 3 -eq 1) { "#FF4FB9FF" } else { "#FF916BFF" })
            $ring.RenderTransform.Angle = ($index * 29.0 + $time * $(if ($index % 2 -eq 0) { 82.0 } else { -64.0 })) % 360.0
            $ring.StrokeDashOffset = $time * $(if ($index % 2 -eq 0) { 18.0 } else { -15.0 })
            $ring.Opacity = 0.30 + 0.055 * $index
            }
        }
    }

    if ($isNeutron) {
        if ($stageChanged) {
            Set-CenteredSize $NeutronBeamAura 410 66
            Set-CenteredSize $NeutronBeamGlow 390 34
            Set-CenteredSize $NeutronBeam 382 7
            Set-CenteredSize $NeutronBeamHot 372 2
        }
        $NeutronAngle = ($time * 572.9578) % 360.0
        $NeutronBeamAura.RenderTransform.Angle = $NeutronAngle
        $NeutronBeam.RenderTransform.Angle = $NeutronAngle
        $NeutronBeamGlow.RenderTransform.Angle = $NeutronAngle
        $NeutronBeamHot.RenderTransform.Angle = $NeutronAngle
        $NeutronBeamAura.Opacity = 0.46 + 0.18 * [Math]::Sin($time * 16.0)
        $NeutronBeam.Opacity = 1.0
        $NeutronBeamGlow.Opacity = 0.92
        $NeutronBeamHot.Opacity = 1.0
    }

    if ($isQuasar) {
        if ($stageChanged) {
            Set-CenteredSize $JetAura 94 360
            Set-CenteredSize $JetGlow 46 350
            Set-CenteredSize $JetCore 10 342
            Set-CenteredSize $DiskAura 330 88
            Set-CenteredSize $DiskOuter 302 72
            Set-CenteredSize $DiskGlow 270 62
            Set-CenteredSize $Disk 250 46
            Set-CenteredSize $DiskHot 220 34
            Set-CenteredSize $BlackCore 92 92
            $JetGlow.Opacity = 0.92
            $JetCore.Opacity = 1.0
            $DiskOuter.Opacity = 0.90
            $DiskGlow.Opacity = 0.85
            $Disk.Opacity = 1.0
            $DiskHot.Opacity = 1.0
            $BlackCore.Opacity = 1.0
            $DiskFrontGlow.Opacity = 0.88
            $DiskFront.Opacity = 1.0
        }
        $JetAura.Opacity = 0.44 + 0.12 * [Math]::Sin($time * 8.0)
        $DiskAura.Opacity = 0.56 + 0.12 * [Math]::Sin($time * 5.0)
        $spin = ($time * 600.0 * 360.0) % 360.0
        $DiskOuter.StrokeDashOffset = -$spin / 18.0
        $Disk.StrokeDashOffset = $spin / 24.0
        $DiskGlow.StrokeDashOffset = -$spin / 40.0
        $DiskHot.StrokeDashOffset = $spin / 13.0
        $DiskFrontGlow.StrokeDashOffset = -$spin / 24.0
        $DiskFront.StrokeDashOffset = $spin / 24.0
    }

    for ($index = 0; $index -lt $ParticleDots.Count; $index++) {
        $dot = $ParticleDots[$index]
        $dot.Opacity = 0.0
        if ($isNormal) {
            $travel = ($time * (0.16 + ($index % 5) * 0.018) + $index * 0.6180339) % 1.0
            $angle = $index * 2.39996 + $time * (0.16 + $level * 0.25)
            $radius = $diameter * (0.50 + 1.85 * $travel)
            [Windows.Controls.Canvas]::SetLeft($dot, $VisualCenterX + [Math]::Cos($angle) * $radius - $dot.Width / 2.0)
            [Windows.Controls.Canvas]::SetTop($dot, $VisualCenterY + [Math]::Sin($angle) * $radius - $dot.Height / 2.0)
            $dot.Fill = $stageBrush
            $dot.Opacity = (1.0 - $travel) * (0.38 + 0.55 * $level)
        }
        elseif ($isNeutron) {
            $travel = ($time * (1.8 + ($index % 4) * 0.13) + $index / [double]$ParticleDots.Count) % 1.0
            $distance = ($travel - 0.5) * 390.0
            $radians = $NeutronAngle * [Math]::PI / 180.0
            $jitter = [Math]::Sin($time * 18.0 + $index) * 2.5
            $x = $VisualCenterX + [Math]::Cos($radians) * $distance - [Math]::Sin($radians) * $jitter
            $y = $VisualCenterY + [Math]::Sin($radians) * $distance + [Math]::Cos($radians) * $jitter
            [Windows.Controls.Canvas]::SetLeft($dot, $x - $dot.Width / 2.0)
            [Windows.Controls.Canvas]::SetTop($dot, $y - $dot.Height / 2.0)
            $dot.Fill = [Windows.Media.Brushes]::White
            $dot.Opacity = 0.28 + 0.70 * [Math]::Sin([Math]::PI * $travel)
        }
        elseif ($isQuasar) {
            if ($index -lt 21) {
                $direction = if ($index % 2 -eq 0) { 1.0 } else { -1.0 }
                $angle = $index * 2.39996 + $direction * $time * (12.0 + ($index % 6))
                $radius = 76.0 + ($index % 9) * 11.0
                $x0 = [Math]::Cos($angle) * $radius
                $y0 = [Math]::Sin($angle) * (13.0 + ($index % 5) * 2.8)
                $x = $VisualCenterX + $x0 * $script:QuasarTiltCos - $y0 * $script:QuasarTiltSin
                $y = $VisualCenterY + $x0 * $script:QuasarTiltSin + $y0 * $script:QuasarTiltCos
                [Windows.Controls.Canvas]::SetLeft($dot, $x - $dot.Width / 2.0)
                [Windows.Controls.Canvas]::SetTop($dot, $y - $dot.Height / 2.0)
                $dot.Fill = if ($index % 3 -eq 0) { [Windows.Media.Brushes]::White } elseif ($index % 3 -eq 1) { [Windows.Media.Brushes]::DeepPink } else { [Windows.Media.Brushes]::Orange }
                $dot.Opacity = 0.42 + 0.55 * (0.5 + 0.5 * [Math]::Sin($time * 13.0 + $index))
            }
            else {
                $travel = ($time * 1.9 + ($index - 21) / 7.0) % 1.0
                $distance = ($travel - 0.5) * 350.0
                $jitter = [Math]::Sin($time * 22.0 + $index) * (4.0 + 8.0 * [Math]::Abs($travel - 0.5))
                $x = $VisualCenterX + $script:QuasarAxisCos * $distance - $script:QuasarAxisSin * $jitter
                $y = $VisualCenterY + $script:QuasarAxisSin * $distance + $script:QuasarAxisCos * $jitter
                [Windows.Controls.Canvas]::SetLeft($dot, $x - $dot.Width / 2.0)
                [Windows.Controls.Canvas]::SetTop($dot, $y - $dot.Height / 2.0)
                $dot.Fill = [Windows.Media.Brushes]::White
                $dot.Opacity = 0.34 + 0.64 * [Math]::Sin([Math]::PI * $travel)
            }
        }
    }

    if ($time -ge $script:NextUiRefresh -or [string]::IsNullOrEmpty($script:LastMassLayoutKey)) {
        $script:NextUiRefresh = $time + 1.0
        $windowSize = Get-BreakdownToken $State.breakdown 'context_window_size' 0L
        $massLabel = "MASS $(Format-Mass ([long]$State.tokens))"
        if ($windowSize -gt 0) { $massLabel += " / $(Format-Mass $windowSize)" }
        $rateSummary = Get-RateSummary
        $sessionSummary = Get-SessionSummary
        $secondarySummary = if ($sessionSummary) { "$sessionSummary | $rateSummary" } else { $rateSummary }
        $detailsContent = Get-DetailsText
        if ($detailsContent -ne $script:LastDetailsText) {
            $script:LastDetailsText = $detailsContent
            $DetailsText.Text = $detailsContent
        }
        $positionKey = "{0},{1}" -f [Math]::Round($Window.Left), [Math]::Round($Window.Top)
        $massLayoutKey = "$massLabel|$stage|$secondarySummary|$($script:StarScaleLevel)|$($script:GrowWithTokens)|$($script:DetailsOpen)|$positionKey"
        if ($massLayoutKey -ne $script:LastMassLayoutKey) {
            $script:LastMassLayoutKey = $massLayoutKey
            $MassText.Text = $massLabel
            $RateText.Text = " | $secondarySummary"
            $MassPanel.Width = [double]::NaN
            $MassPanel.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
            $detailsWasCollapsed = $DetailsPanel.Visibility -eq "Collapsed"
            if ($detailsWasCollapsed) { $DetailsPanel.Visibility = "Hidden" }
            $DetailsPanel.Measure([Windows.Size]::new($DetailsPanel.Width, [double]::PositiveInfinity))
            if ($detailsWasCollapsed) { $DetailsPanel.Visibility = "Collapsed" }
            $panelWidth = [Math]::Max(112.0, $MassPanel.DesiredSize.Width)
            $visualClearance = switch ($stage) {
                "RED DWARF" { 180.0 }
                "MAIN SEQUENCE" { 250.0 }
                "BLUE GIANT" { 340.0 }
                "HYPERGIANT" { 360.0 }
                "NEUTRON STAR" { 230.0 }
                default { 200.0 }
            }
            $visualClearance = [Math]::Max(48.0, $visualClearance * $starMultiplier)
            $panelHeight = [double]$MassPanel.DesiredSize.Height
            $detailsHeight = [double]$DetailsPanel.DesiredSize.Height
            $gap = 7.0
            $panelLeft = $CenterX - $panelWidth / 2.0
            $detailsLeft = $CenterX - [double]$DetailsPanel.Width / 2.0
            $panelTop = $CenterY + $visualClearance + 12.0
            $detailsTop = $panelTop + $panelHeight + $gap
            [Windows.Controls.Canvas]::SetLeft($MassPanel, $panelLeft)
            [Windows.Controls.Canvas]::SetTop($MassPanel, $panelTop)
            [Windows.Controls.Canvas]::SetLeft($DetailsPanel, $detailsLeft)
            [Windows.Controls.Canvas]::SetTop($DetailsPanel, $detailsTop)
            $requiredBottom = if ($script:DetailsOpen) { $detailsTop + $detailsHeight + 12.0 } else { $panelTop + $panelHeight + 12.0 }
            Set-WindowFootprint $requiredBottom
        }
    }
    $MassPanel.Opacity = if ($visible -or $SelfTest) {
        if ($script:InteractivePanelActive -or $SelfTest) { 0.96 } else { 0.46 }
    }
    else { 0.0 }
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
            $hit = Get-CursorHitMask
            $script:DragHandleActive = ($hit -band 1) -ne 0
            $script:InteractivePanelActive = ($hit -band 2) -ne 0
            $handled.Value = $true
            if ($hit -ne 0) { return [IntPtr]1 }
            return [IntPtr](-1)
        }
        if ($message -eq 0x0202) {
            $hit = Get-CursorHitMask
            if (($hit -band 2) -ne 0) {
                Toggle-DetailsPanel
                $handled.Value = $true
                return [IntPtr]::Zero
            }
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
    if ((Format-Mass 999999) -ne "1000K" -or (Format-Mass 1000000) -ne "1.00M" -or
        (Format-Mass 1250000) -ne "1.25M") {
        throw "Token Star overlay mass-format self-test failed."
    }
    if ([string]$StageModeComboBox.SelectedItem.Tag -ne $script:StageMode -or
        [bool]$GrowWithTokensCheckBox.IsChecked -ne $script:GrowWithTokens -or
        [bool]$LockPositionCheckBox.IsChecked -ne $script:PositionLocked) {
        throw "Token Star overlay persisted-preferences self-test failed."
    }
    $State.project_name = "ScopedProject"
    if (-not (Test-ProjectWindow ([pscustomobject]@{ Title = "main.py - ScopedProject - PyCharm" }))) {
        throw "Token Star overlay project-title match self-test failed."
    }
    if (Test-ProjectWindow ([pscustomobject]@{ Title = "main.py - OtherProject - PyCharm" })) {
        throw "Token Star overlay project-title isolation self-test failed."
    }
    $panelLeft = [Windows.Controls.Canvas]::GetLeft($MassPanel)
    $panelTop = [Windows.Controls.Canvas]::GetTop($MassPanel)
    $panelPointX = $panelLeft + $MassPanel.DesiredSize.Width / 2.0
    $panelPointY = $panelTop + $MassPanel.DesiredSize.Height / 2.0
    $panelPoint = New-Object Windows.Point($panelPointX, $panelPointY)
    if (-not (Test-PointOverElement $panelPoint $MassPanel 0.0)) {
        throw "Token Star overlay auto-sized panel hit-test self-test failed."
    }
    if ([Math]::Abs(($panelLeft + $MassPanel.DesiredSize.Width / 2.0) - $CenterX) -gt 1.0 -or
        $panelTop -le ($CenterY + 48.0)) {
        throw "Token Star overlay centered-below layout self-test failed."
    }
    $travelRect = New-Object TokenStarNative+RECT
    $travelRect.Left = 0; $travelRect.Top = 0; $travelRect.Right = 1200; $travelRect.Bottom = 800
    $travelBounds = Get-WindowTravelBounds ([pscustomobject]@{ Rect = $travelRect; Scale = 1.0 })
    if ($travelBounds.Width -lt 900.0 -or $travelBounds.Height -lt 600.0) {
        throw "Token Star overlay expanded movement-range self-test failed."
    }
    Set-DraggedWindowPosition -10000.0 -10000.0 ([pscustomobject]@{ Rect = $travelRect; Scale = 1.0 })
    if ([Math]::Abs($Window.Left - $travelBounds.MinLeft) -gt 1.0 -or
        [Math]::Abs($Window.Top - $travelBounds.MinTop) -gt 1.0) {
        throw "Token Star overlay top-left corner drag self-test failed."
    }
    Set-DraggedWindowPosition 10000.0 10000.0 ([pscustomobject]@{ Rect = $travelRect; Scale = 1.0 })
    if ([Math]::Abs($Window.Left - $travelBounds.MaxLeft) -gt 1.0 -or
        [Math]::Abs($Window.Top - $travelBounds.MaxTop) -gt 1.0) {
        throw "Token Star overlay bottom-right corner drag self-test failed."
    }
    $Window.Left = 0.0
    $Window.Top = 0.0
    $Root.Clip = $null
    $DetailsButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    if (-not $script:DetailsOpen -or $DetailsPanel.Visibility -ne "Visible") {
        throw "Token Star overlay details dropdown self-test failed."
    }
    if ($DetailsText.Text -notmatch "Model\s+Opus 5" -or $DetailsText.Text -notmatch "Effort\s+Extra high" -or
        $DetailsText.Text -notmatch "Active sessions\s+2") {
        throw "Token Star overlay model/effort self-test failed."
    }
    $expectedMassText = "MASS $(Format-Mass ([long]$State.tokens)) / $(Format-Mass (Get-BreakdownToken $State.breakdown 'context_window_size' 0L))"
    if ($MassText.Text -ne $expectedMassText) {
        throw "Token Star overlay used/available token self-test failed."
    }
    $Root.Measure((New-Object Windows.Size($CanvasWidth, $CanvasHeight)))
    $Root.Arrange((New-Object Windows.Rect(0, 0, $CanvasWidth, $CanvasHeight)))
    $Root.UpdateLayout()
    $detailsPoint = New-Object Windows.Point(
        ([Windows.Controls.Canvas]::GetLeft($DetailsPanel) + $DetailsPanel.ActualWidth / 2.0),
        ([Windows.Controls.Canvas]::GetTop($DetailsPanel) + $DetailsPanel.ActualHeight / 2.0)
    )
    if (-not (Test-PointOverElement $detailsPoint $DetailsPanel 0.0)) {
        throw "Token Star overlay details-panel hit-test self-test failed."
    }
    $detailsLeft = [Windows.Controls.Canvas]::GetLeft($DetailsPanel)
    $detailsTop = [Windows.Controls.Canvas]::GetTop($DetailsPanel)
    if ([Math]::Abs(($detailsLeft + $DetailsPanel.ActualWidth / 2.0) - $CenterX) -gt 1.0 -or
        $detailsTop -le ($panelTop + $MassPanel.ActualHeight)) {
        throw "Token Star overlay centered details layout self-test failed."
    }
    Set-GrowWithTokens $false $false
    Set-StageMode "AUTO" $false
    $Scale1Button.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    if ($script:StarScaleLevel -ne 1 -or [Math]::Abs([double]$VisualLayer.RenderTransform.ScaleX - (1.0 / 3.0)) -gt 0.0001) {
        throw "Token Star overlay 1x scale self-test failed."
    }
    $Scale3Button.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    if ($script:StarScaleLevel -ne 3 -or [Math]::Abs([double]$VisualLayer.RenderTransform.ScaleX - 1.0) -gt 0.0001) {
        throw "Token Star overlay 3x scale self-test failed."
    }
    Set-StageMode "QUASAR" $false
    if ((Get-EffectiveStage 0.01) -ne "QUASAR" -or [string]$StageModeComboBox.SelectedItem.Tag -ne "QUASAR") {
        throw "Token Star overlay fixed-stage self-test failed."
    }
    $originalLevel = [double]$State.level
    $State.level = 0.0
    Set-GrowWithTokens $true $false
    if ([Math]::Abs([double]$VisualLayer.RenderTransform.ScaleX - 0.65) -gt 0.0001) {
        throw "Token Star overlay token-growth minimum self-test failed."
    }
    $State.level = 1.0
    Apply-StarScale 1.0
    if ([Math]::Abs([double]$VisualLayer.RenderTransform.ScaleX - 1.0) -gt 0.0001) {
        throw "Token Star overlay token-growth maximum self-test failed."
    }
    $State.level = $originalLevel
    Set-GrowWithTokens $false $false
    Set-StageMode "AUTO" $false
    Set-PositionLock $true $false
    if (-not $script:PositionLocked -or $DragHandle.Cursor.ToString() -ne "Arrow") {
        throw "Token Star overlay position-lock self-test failed."
    }
    Set-PositionLock $false $false
    if ($script:PositionLocked -or $DragHandle.Cursor.ToString() -ne "SizeAll") {
        throw "Token Star overlay position-unlock self-test failed."
    }
    if (-not $CaptureDetails) {
        $DetailsButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    }
    if (-not [string]::IsNullOrWhiteSpace($CapturePath)) {
        Start-Sleep -Milliseconds 420
        Update-Visual
        $captureFullPath = [IO.Path]::GetFullPath($CapturePath)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $captureFullPath)) | Out-Null
        $captureBackground = $Root.Background
        try {
            $Root.Background = Get-SolidBrush "#FF070B12"
            $Root.Measure((New-Object Windows.Size($CanvasWidth, $CanvasHeight)))
            $Root.Arrange((New-Object Windows.Rect(0, 0, $CanvasWidth, $CanvasHeight)))
            $Root.UpdateLayout()
            $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$CanvasWidth, [int]$CanvasHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($Root)
            $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream = [IO.File]::Open($captureFullPath, [IO.FileMode]::Create)
            try { $encoder.Save($stream) }
            finally { $stream.Dispose() }
        }
        finally { $Root.Background = $captureBackground }
        Write-Output "Captured $captureFullPath"
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
$Timer.Interval = [TimeSpan]::FromMilliseconds(300)
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
