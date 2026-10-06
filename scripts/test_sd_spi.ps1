param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
Invoke-Checked 'git' @('diff','--exit-code','--diff-filter=MDRT','80cc06f','--','src/rtl','scripts','constraints','sw/freertos')
Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') @('--nolog','--sv','-work','sd_unit','src/rtl/peripheral/sd_spi.v','src/sim/tb_sd_spi.sv')
Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps','sd_unit.tb_sd_spi','-s','sd_spi_unit_sim','-debug','typical')
$output=& (Join-Path $VivadoBin 'xsim.bat') 'sd_spi_unit_sim' '--nolog' '-runall' 2>&1
$exitCode=$LASTEXITCODE
$output | ForEach-Object {Write-Host $_}
if($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or ($output -join "`n") -notmatch 'SD SPI UNIT PASS') {throw 'SD SPI unit failed'}
