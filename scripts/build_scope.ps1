$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$Hex = Join-Path $Root 'build/hex/scope.hex'
python.exe -E scripts/build_guard.py begin --kind firmware --file $Hex
if ($LASTEXITCODE -ne 0) { throw 'Cannot start scope firmware build' }
New-Item -ItemType Directory -Path (Split-Path -Parent $Hex) -Force | Out-Null
python.exe -E sw/tools/rv32asm.py sw/firmware/scope.S $Hex
if ($LASTEXITCODE -ne 0) { throw 'Scope firmware build failed' }
python.exe -E scripts/build_guard.py finish --kind firmware --file $Hex
if ($LASTEXITCODE -ne 0) { throw 'Scope firmware inputs changed during build' }
Write-Host "SCOPE BUILD PASS: $Hex"
