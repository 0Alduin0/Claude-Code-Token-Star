[CmdletBinding()]
param(
    [int]$FrameCount = 16,
    [int]$FrameIntervalMs = 150
)

$ErrorActionPreference = "Stop"
$RepoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$OverlayPath = Join-Path $RepoRoot "src\windows\token-star-overlay.ps1"
$OutputRoot = Join-Path $RepoRoot "assets\preview"
$FrameRoot = Join-Path $RepoRoot ".tmp-ui\preview-frames"
$ffmpeg = Get-Command ffmpeg -ErrorAction Stop

$resolvedFrameRoot = [IO.Path]::GetFullPath($FrameRoot)
if (-not $resolvedFrameRoot.StartsWith($RepoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Preview frame directory escaped the repository."
}
if (Test-Path -LiteralPath $resolvedFrameRoot) {
    Remove-Item -LiteralPath $resolvedFrameRoot -Recurse -Force
}
[IO.Directory]::CreateDirectory($resolvedFrameRoot) | Out-Null
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null

$stages = @(
    [pscustomobject]@{ Slug = "red-dwarf"; Level = 0.07 },
    [pscustomobject]@{ Slug = "main-sequence"; Level = 0.25 },
    [pscustomobject]@{ Slug = "blue-giant"; Level = 0.45 },
    [pscustomobject]@{ Slug = "hypergiant"; Level = 0.65 },
    [pscustomobject]@{ Slug = "neutron-star"; Level = 0.82 },
    [pscustomobject]@{ Slug = "quasar"; Level = 0.95 }
)
$fps = (1000.0 / [Math]::Max(1, $FrameIntervalMs)).ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)

try {
    foreach ($stage in $stages) {
        $stageRoot = Join-Path $resolvedFrameRoot $stage.Slug
        [IO.Directory]::CreateDirectory($stageRoot) | Out-Null
        $captureBase = Join-Path $stageRoot ($stage.Slug + ".png")
        & powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass `
            -File $OverlayPath -SelfTest -Demo -DemoLevel $stage.Level `
            -CapturePath $captureBase -CaptureFrames $FrameCount `
            -CaptureFrameIntervalMs $FrameIntervalMs -CaptureTransparent -CaptureVisualOnly
        if ($LASTEXITCODE -ne 0) { throw "WPF capture failed for $($stage.Slug)." }

        $inputPattern = Join-Path $stageRoot ($stage.Slug + "-%03d.png")
        $outputPath = Join-Path $OutputRoot ("overlay-{0}.webp" -f $stage.Slug)
        & $ffmpeg.Source -hide_banner -loglevel error -y -framerate $fps -i $inputPattern `
            -vf "format=rgba" -c:v libwebp_anim -lossless 1 `
            -compression_level 2 -loop 0 -an $outputPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
            throw "Animated WebP encoding failed for $($stage.Slug)."
        }
        Write-Output "Generated $outputPath"
    }
}
finally {
    if (Test-Path -LiteralPath $resolvedFrameRoot) {
        Remove-Item -LiteralPath $resolvedFrameRoot -Recurse -Force
    }
}
