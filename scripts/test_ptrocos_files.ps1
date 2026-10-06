param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix,
    [ValidateSet(0,1)][int[]]$PcStyle=@(0,1),[switch]$CompileOnly,[switch]$RunOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
if($CompileOnly -and $RunOnly) {throw 'CompileOnly and RunOnly are mutually exclusive.'}
if($ToolchainPrefix) {
    if($RunOnly) {throw 'Build before RunOnly.'}
    & "$PSScriptRoot/build_ptrocos.ps1" -Firmware storage -ToolchainPrefix $ToolchainPrefix
}
if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_storage.hex')) {throw 'Build storage firmware first.'}
Invoke-Checked 'git' @('diff','--exit-code','--diff-filter=MDRT','80cc06f','--','src/rtl','scripts','constraints','sw/freertos')
if(-not $RunOnly) {
    Invoke-Checked 'python.exe' @('sw/tools/gen_fatfs_image.py','--files')
    $sources=@(Get-Content -LiteralPath 'scripts/ptrocos_sources.txt')+@('src/sim/axi_sparse_memory.sv',
        'src/sim/sd_spi_card_model.sv','src/sim/tb_ptrocos_files.sv')
    Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','files_soc')+$sources)
    foreach($style in $PcStyle) {
        $top=if($style -eq 0) {'tb_ptrocos_files'} else {'tb_ptrocos_files_alt'}
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"files_soc.$top",'-s',"${top}_soc_sim",'-debug','typical')
    }
}
if($CompileOnly) {Write-Host 'PTROCOS FILE COMMANDS COMPILE PASS';return}
foreach($style in $PcStyle) {
    $top=if($style -eq 0) {'tb_ptrocos_files'} else {'tb_ptrocos_files_alt'}
    $output=& (Join-Path $VivadoBin 'xsim.bat') "${top}_soc_sim" '--nolog' '-runall' 2>&1 |
        Tee-Object -FilePath "build/ptrocos_files/${top}.runtime.log"
    $exitCode=$LASTEXITCODE
    $output | ForEach-Object {Write-Host $_}
    $joined=$output -join "`n"
    if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch 'PTROCOS FILE COMMANDS SOC PASS') {throw "$top failed"}
}
Write-Host 'PTROCOS FILE COMMANDS INTEGRATION TEST PASS'
