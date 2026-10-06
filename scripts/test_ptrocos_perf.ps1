param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix,
    [ValidateSet(0,1)][int[]]$PcStyle=@(0,1),[switch]$CompileOnly,[switch]$RunOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
if($CompileOnly -and $RunOnly) {throw 'Incompatible switches'}
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
New-Item -ItemType Directory -Path build/ptrocos_perf -Force | Out-Null
if($ToolchainPrefix) {
    if($RunOnly) {throw 'Build before RunOnly'}
    & "$PSScriptRoot/build_ptrocos.ps1" -Firmware perf -ToolchainPrefix $ToolchainPrefix
}
if(-not (Test-Path -LiteralPath build/hex/ptrocos_perf.hex)) {throw 'Build perf firmware first'}
Invoke-Checked 'git' @('diff','--exit-code','2894f42','--','src/rtl','sw/freertos','sw/ptrocos/media','sw/ptrocos/graphics.c')
if(-not $RunOnly) {
    $sources=@(Get-Content scripts/ptrocos_sources.txt)+@('src/sim/axi_sparse_memory.sv','src/sim/tb_ptrocos_perf.sv')
    Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','perf_soc')+$sources)
    foreach($style in $PcStyle) {
        $top=if($style -eq 0) {'tb_ptrocos_perf'} else {'tb_ptrocos_perf_alt'}
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"perf_soc.$top",'-s',"${top}_sim",'--O3','-debug','off')
    }
}
if($CompileOnly) {Write-Host 'PTROCOS PERF COMPILE PASS';return}
foreach($style in $PcStyle) {
    $top=if($style -eq 0) {'tb_ptrocos_perf'} else {'tb_ptrocos_perf_alt'}
    $output=& (Join-Path $VivadoBin 'xsim.bat') "${top}_sim" '--nolog' '-runall' '-onfinish' 'quit' 2>&1
    $exitCode=$LASTEXITCODE
    $output | Set-Content -LiteralPath "build/ptrocos_perf/runtime.style$style.log" -Encoding utf8
    $output | ForEach-Object {Write-Host $_}
    $joined=$output -join "`n"
    if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch "PTROCOS PERF SOC PASS style=$style") {throw "Performance style $style failed"}
}
Write-Host 'PTROCOS PERF TEST PASS'
