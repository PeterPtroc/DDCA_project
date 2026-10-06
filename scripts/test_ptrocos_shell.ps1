param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
if($ToolchainPrefix) {& "$PSScriptRoot/build_ptrocos.ps1" -Firmware shell -ToolchainPrefix $ToolchainPrefix}
if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_shell.hex')) {throw 'Build shell firmware first.'}
Invoke-Checked 'python.exe' @('sw/tools/check_tty.py')
Invoke-Checked 'git' @('diff','--exit-code','--diff-filter=MDRT','80cc06f','--','src/rtl','scripts','constraints','sw/freertos')
$sources=@(Get-Content -LiteralPath 'scripts/ptrocos_sources.txt')+@('src/sim/axi_sparse_memory.sv','src/sim/tb_ptrocos_shell.sv')
Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','shell_soc')+$sources)
foreach($top in @('tb_ptrocos_shell','tb_ptrocos_shell_alt')) {
    $snapshot="${top}_soc_sim"
    Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"shell_soc.$top",'-s',$snapshot,'-debug','typical')
    $output=& (Join-Path $VivadoBin 'xsim.bat') $snapshot '--nolog' '-runall' 2>&1
    $exitCode=$LASTEXITCODE
    $output | ForEach-Object {Write-Host $_}
    if($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or ($output -join "`n") -notmatch 'PTROCOS SHELL SOC PASS') {throw "$top failed"}
}
Write-Host 'PTROCOS SHELL INTEGRATION TEST PASS'
