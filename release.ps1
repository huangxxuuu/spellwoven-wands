#!/usr/bin/env pwsh
# See docs/发布流程.txt: review -> human-approved notes -> prepare -> commit -> publish.
# Code releases preserve Workshop preview/title/description. Python never invokes a shell.
$ErrorActionPreference = 'Stop'
$python = Join-Path $PSScriptRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) { $python = 'python' }
& $python (Join-Path $PSScriptRoot 'tools/release.py') @args
exit $LASTEXITCODE
