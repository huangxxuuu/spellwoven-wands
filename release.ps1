#!/usr/bin/env pwsh
# Forward all arguments to the release coordinator; Python never invokes a shell.
$ErrorActionPreference = 'Stop'
$python = Join-Path $PSScriptRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) { $python = 'python' }
& $python (Join-Path $PSScriptRoot 'tools/release.py') @args
exit $LASTEXITCODE
