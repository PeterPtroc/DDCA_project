param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
if($ToolchainPrefix) {& "$PSScriptRoot/build_ptrocos.ps1" -Firmware text -ToolchainPrefix $ToolchainPrefix}
if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_text.hex')) {throw 'Build text firmware first.'}
Invoke-Checked 'git' @('diff','--exit-code','191da2f','--',
    'src/rtl/cpu/rv32_core.v','src/rtl/cpu/rv32im_core.v','src/rtl/cpu/rv32im_decoder.v',
    'src/rtl/cpu/rv32m_unit.v','src/rtl/cpu/decoder.v','src/rtl/top/soc_top.v',
    'src/rtl/top/nexys_a7_top.v','scripts/create_vivado_project.tcl','scripts/test.ps1',
    'constraints/nexys_a7_100t.xdc','sw/freertos')
$sources=@(Get-Content -LiteralPath 'scripts/ptrocos_sources.txt')+@('src/sim/axi_sparse_memory.sv','src/sim/tb_ptrocos_text.sv')
Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','text_soc')+$sources)
foreach($top in @('tb_ptrocos_text','tb_ptrocos_text_alt')) {
    $snapshot="${top}_soc_sim"
    Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"text_soc.$top",'-s',$snapshot,'-debug','typical')
    $output=& (Join-Path $VivadoBin 'xsim.bat') $snapshot '--nolog' '-runall' 2>&1
    $exitCode=$LASTEXITCODE
    $output | ForEach-Object {Write-Host $_}
    if($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or ($output -join "`n") -notmatch 'PTROCOS TEXT SOC PASS') {throw "$top failed"}
}
Write-Host 'PTROCOS TEXT INTEGRATION TEST PASS'
