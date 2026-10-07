param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin', [string]$ToolchainPrefix)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
function Invoke-Checked {
    param([string]$Command,[string[]]$Arguments)
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) { throw "$Command failed: $LASTEXITCODE" }
}
if($ToolchainPrefix) { & "$PSScriptRoot/build_ptrocos.ps1" -ToolchainPrefix $ToolchainPrefix }
if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_ddr2.hex')) { throw 'Build PtrocOS DDR2 firmware first.' }
$sources=@(Get-Content -LiteralPath 'scripts/ptrocos_sources.txt')+
    @('src/sim/axi_sparse_memory.sv','src/sim/tb_ptrocos_ddr2.sv')
Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','ptrocos_soc')+$sources)
foreach($top in @('tb_ptrocos_ddr2','tb_ptrocos_ddr2_alt')) {
    $snapshot="${top}_soc_sim"
    Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"ptrocos_soc.$top",'-s',$snapshot,'-debug','typical')
    $output=& (Join-Path $VivadoBin 'xsim.bat') $snapshot '--nolog' '-runall' 2>&1
    $exitCode=$LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or
        ($output -join "`n") -notmatch 'PTROCOS DDR2 SOC PASS') { throw "Simulation $top failed" }
}
Invoke-Checked 'python.exe' @('sw/tools/check_ptrocos_ddr2.py')
Write-Host 'PTROCOS DDR2 INTEGRATION TEST PASS (sparse AXI model; physical MIG and board tests remain separate)'
