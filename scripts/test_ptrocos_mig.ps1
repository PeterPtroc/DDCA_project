param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[switch]$FullDiagnostic)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
function Invoke-Checked {
    param([string]$Command,[string[]]$Arguments)
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) { throw "$Command failed: $LASTEXITCODE" }
}
$ip='build/ptrocos_ddr2/ptrocos_ddr2.gen/sources_1/ip/ptrocos_ddr2_mig/ptrocos_ddr2_mig'
$rtl=Join-Path $ip 'user_design/rtl'
$sim=Join-Path $ip 'example_design/sim'
if(-not (Test-Path -LiteralPath $rtl)) { throw 'Run create_ddr2_ip.tcl first.' }
if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_ddr2.hex')) { throw 'Build PtrocOS DDR2 firmware first.' }
$sources=@(Get-Content -LiteralPath 'scripts/ptrocos_sources.txt')+@('src/rtl/top/ptrocos_nexys_a7_top.v')
# Simulation and synthesis variants declare the same module. Only the generated
# simulation variant (SIMULATION=TRUE, FAST calibration) is compiled here.
$sources+=@(Get-ChildItem -LiteralPath $rtl -Recurse -Filter '*.v' |
    Where-Object { $_.Name -ne 'ptrocos_ddr2_mig_mig.v' } | ForEach-Object { $_.FullName })
$sources+=@((Join-Path $sim 'ddr2_model.v'),'src/sim/tb_ptrocos_mig.sv',
    (Join-Path (Split-Path -Parent $VivadoBin) 'data/verilog/src/glbl.v'))
$project='build/ptrocos_ddr2/mig_sim.prj'
$sources | ForEach-Object {
    $language=if($_.EndsWith('.sv')) { 'sv' } else { 'verilog' }
    '{0} ptrocos_mig "{1}"' -f $language,((Resolve-Path -LiteralPath $_).Path.Replace('\','/'))
} | Set-Content -LiteralPath $project -Encoding ascii
$arguments=@('--nolog','--prj',$project,'-i',$sim,'-d','x1Gb','-d','sg25E','-d','x16')
if($FullDiagnostic) { $arguments+=@('-d','PTROCOS_MIG_FULL_DIAGNOSTIC') }
Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') $arguments
Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',
    'ptrocos_mig.tb_ptrocos_mig','ptrocos_mig.glbl','-L','unisims_ver','-L','secureip',
    '-s','ptrocos_mig_pin_sim','-debug','typical')
$output=& (Join-Path $VivadoBin 'xsim.bat') 'ptrocos_mig_pin_sim' '--nolog' '-runall' 2>&1 |
    Tee-Object -FilePath 'build/ptrocos_ddr2/mig-runtime.log'
$exitCode=$LASTEXITCODE
$marker=if($FullDiagnostic) { 'PTROCOS MIG PIN SIM PASS' } else { 'PTROCOS MIG LINK SMOKE PASS' }
if($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or
    ($output -join "`n") -notmatch $marker) { throw 'MIG pin simulation failed' }
Write-Host 'PTROCOS MIG SIMULATION PASS (simulation FAST calibration; hardware calibration remains required)'
