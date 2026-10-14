# Create the Windows runner from the installed Flutter toolchain, preserving lib/,
# assets/, Android signing and the existing application pubspec.
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Destination = Join-Path $Repo 'windows'
if (Test-Path $Destination) {
    Write-Host 'Windows runner already exists; keeping existing customisations.'
    exit 0
}
$Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('flavorflow-windows-' + [guid]::NewGuid())
try {
    & flutter create --platforms=windows --project-name=flavorflow_erp --org=in.flavorflow --no-pub $Scratch
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows runner generation failed.' }
    Copy-Item -Path (Join-Path $Scratch 'windows') -Destination $Destination -Recurse
    $Main = Join-Path $Destination 'runner/main.cpp'
    $Text = [System.IO.File]::ReadAllText($Main).Replace('L"flavorflow_erp"', 'L"FlavorFlow ERP"')
    [System.IO.File]::WriteAllText($Main, $Text)
    $Icon = Join-Path $Repo 'tools/windows/app_icon.ico'
    if (Test-Path $Icon) {
        Copy-Item $Icon (Join-Path $Destination 'runner/resources/app_icon.ico') -Force
    }
    Write-Host 'Windows runner created. The existing ERP Dart code and assets are unchanged.'
} finally {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
}
