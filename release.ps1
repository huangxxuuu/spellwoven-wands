#!/usr/bin/env pwsh
# See docs/发布流程.txt: approved release material -> --mode all (quiet end-to-end).
# Code releases preserve Workshop preview/title/description. Python never invokes a shell.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try {
    $releasePython = Join-Path $PSScriptRoot '.venv/Scripts/python.exe'
    if (-not (Test-Path -LiteralPath $releasePython -PathType Leaf)) {
        $releasePython = (Get-Command python -ErrorAction Stop).Source
    }
    & $releasePython (Join-Path $PSScriptRoot 'tools/release.py') @args
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine('FAILED [launcher]: ' + ($_.Exception.Message -replace '[\r\n]+', ' '))
    exit 1
}
