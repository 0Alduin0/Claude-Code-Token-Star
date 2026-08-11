$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Shader = Join-Path $Root "supernova-windows.hlsl"
$Output = Join-Path $env:TEMP "ghostty-supernova-windows-test.cso"

$Compiler = Get-Command fxc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
if (-not $Compiler) {
    $KitRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (Test-Path -LiteralPath $KitRoot) {
        $Compiler = Get-ChildItem -LiteralPath $KitRoot -Filter fxc.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\x64\\fxc\.exe$" } |
            Sort-Object FullName -Descending |
            Select-Object -ExpandProperty FullName -First 1
    }
}
if (-not $Compiler) { throw "fxc.exe was not found in the Windows SDK." }

try {
    & $Compiler /nologo /T ps_4_0 /E main /Fo $Output $Shader
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Output)) {
        throw "HLSL compilation failed."
    }
    Write-Output "supernova-windows.hlsl: HLSL syntax OK"
}
finally {
    if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output -Force }
}
