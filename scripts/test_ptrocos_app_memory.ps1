param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Path build/ptrocos_elf -Force | Out-Null
& (Join-Path $VivadoBin 'xvlog.bat') --nolog --sv -work app_memory src/rtl/memory/word_bus_cdc.v src/rtl/memory/ptrocos_app_memory.v src/sim/tb_ptrocos_app_memory.sv
if($LASTEXITCODE -ne 0) {throw 'App memory compile failed'}
& (Join-Path $VivadoBin 'xelab.bat') --nolog --timescale 1ns/1ps app_memory.tb_ptrocos_app_memory -s app_memory_sim --O3 -debug off
if($LASTEXITCODE -ne 0) {throw 'App memory elaborate failed'}
$output=& (Join-Path $VivadoBin 'xsim.bat') app_memory_sim --nolog -runall -onfinish quit 2>&1
$exitCode=$LASTEXITCODE
$output | Set-Content -LiteralPath build/ptrocos_elf/app-unit.runtime.log -Encoding utf8
$output | ForEach-Object {Write-Host $_};$joined=$output -join "`n"
if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch 'PTROCOS APP MEMORY UNIT PASS') {throw 'App memory unit failed'}
Write-Host 'PTROCOS APP MEMORY TEST PASS'
