$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (-not (Test-Path 'windows/runner/main.cpp')) {
        flutter create --platforms=windows --org in.flavorflow --project-name flavorflow_erp .
        if ($LASTEXITCODE -ne 0) {
            throw "flutter create failed with exit code $LASTEXITCODE."
        }
    }

    $mainFile = 'windows/runner/main.cpp'
    $mainSource = Get-Content $mainFile -Raw
    $titlePattern = 'window\.Create\(L"[^"]+"'
    if ($mainSource -notmatch $titlePattern) {
        throw "Could not locate the Windows title in $mainFile."
    }
    $mainSource = [regex]::Replace(
        $mainSource,
        $titlePattern,
        'window.Create(L"FlavorFlow ERP"'
    )
    [System.IO.File]::WriteAllText(
        $mainFile,
        $mainSource,
        [System.Text.UTF8Encoding]::new($false)
    )

    $cmakeFile = 'windows/CMakeLists.txt'
    $cmakeSource = Get-Content $cmakeFile -Raw
    $compatibilityDefine = 'add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)'
    if (-not $cmakeSource.Contains($compatibilityDefine)) {
        # VS 18 / MSVC 14.51 currently promotes this legacy /await warning in
        # local_auth_windows and permission_handler_windows to a build error.
        # Remove this compatibility define after those plugins stop using the
        # deprecated <experimental/coroutine> header.
        $projectLine = [regex]::Match($cmakeSource, '(?m)^project\([^\r\n]+\)')
        if (-not $projectLine.Success) {
            throw "Could not locate the project() declaration in $cmakeFile."
        }
        $insertAt = $projectLine.Index + $projectLine.Length
        $cmakeSource = $cmakeSource.Insert($insertAt, [Environment]::NewLine + $compatibilityDefine)
        [System.IO.File]::WriteAllText(
            $cmakeFile,
            $cmakeSource,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
}
finally {
    Pop-Location
}
