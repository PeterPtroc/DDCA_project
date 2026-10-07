param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
if($ToolchainPrefix) {& "$PSScriptRoot/build_ptrocos.ps1" -Firmware storage -ToolchainPrefix $ToolchainPrefix}
if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_storage.hex')) {throw 'Build storage firmware first.'}
Invoke-Checked 'python.exe' @('sw/tools/gen_fatfs_image.py')
$sources=@(Get-Content -LiteralPath 'scripts/ptrocos_sources.txt')+@('src/sim/axi_sparse_memory.sv',
    'src/sim/sd_spi_card_model.sv','src/sim/tb_ptrocos_storage.sv')
Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','storage_soc')+$sources)
foreach($top in @('tb_ptrocos_storage','tb_ptrocos_storage_alt')) {
    $snapshot="${top}_soc_sim"
    Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"storage_soc.$top",'-s',$snapshot,'-debug','typical')
    $output=& (Join-Path $VivadoBin 'xsim.bat') $snapshot '--nolog' '-runall' 2>&1 |
        Tee-Object -FilePath "build/ptrocos_storage/${top}.runtime.log"
    $exitCode=$LASTEXITCODE
    $output | ForEach-Object {Write-Host $_}
    if($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or ($output -join "`n") -notmatch 'PTROCOS STORAGE SOC PASS') {throw "$top failed"}
}
Write-Host 'PTROCOS STORAGE INTEGRATION TEST PASS'
