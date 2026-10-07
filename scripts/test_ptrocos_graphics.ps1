param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix,
    [ValidateSet(0,1)][int[]]$PcStyle=@(0,1),[switch]$UnitOnly,[switch]$SocOnly,
    [switch]$CompileOnly,[switch]$RunOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
if(($CompileOnly -and $RunOnly) -or ($UnitOnly -and $SocOnly)) {throw 'Incompatible switches.'}
if($ToolchainPrefix) {
    if($RunOnly) {throw 'Build before RunOnly.'}
    & "$PSScriptRoot/build_ptrocos.ps1" -Firmware graphics -ToolchainPrefix $ToolchainPrefix
}
New-Item -ItemType Directory -Path 'build/ptrocos_graphics' -Force | Out-Null
if(-not $RunOnly) {Invoke-Checked 'python.exe' @('sw/tools/gen_graphics_pattern.py')}
$tests=@()
if(-not $SocOnly) {
    if(-not $RunOnly) {
        $sources=@('src/rtl/memory/word_bus_cdc.v','src/rtl/memory/axi_read_arbiter.v',
            'src/rtl/video/vga_ddr_framebuffer.v','src/sim/axi_graphics_memory.sv','src/sim/tb_vga_ddr_framebuffer.sv')
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','graphics_unit')+$sources)
    }
    foreach($top in @('tb_vga_ddr_framebuffer','tb_vga_ddr_framebuffer_full')) {
        if(-not $RunOnly) {
            Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"graphics_unit.$top",'-s',"${top}_unit_sim",'-debug','typical')
        }
        $tests+=[pscustomobject]@{Snapshot="${top}_unit_sim";Marker='DDR FRAMEBUFFER UNIT PASS';Log="build/ptrocos_graphics/${top}.runtime.log"}
    }
}
if(-not $UnitOnly) {
    if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_graphics.hex')) {throw 'Build graphics firmware first.'}
    if(-not $RunOnly) {
        $sources=@(Get-Content -LiteralPath 'scripts/ptrocos_sources.txt')+@('src/sim/axi_graphics_memory.sv','src/sim/tb_ptrocos_graphics.sv')
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','graphics_soc')+$sources)
    }
    foreach($style in $PcStyle) {
        $top=if($style -eq 0) {'tb_ptrocos_graphics'} else {'tb_ptrocos_graphics_alt'}
        if(-not $RunOnly) {
            Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"graphics_soc.$top",'-s',"${top}_soc_sim",'-debug','typical')
        }
        $tests+=[pscustomobject]@{Snapshot="${top}_soc_sim";Marker='PTROCOS GRAPHICS SOC PASS';Log="build/ptrocos_graphics/${top}.runtime.log"}
    }
}
if($CompileOnly) {Write-Host 'PTROCOS GRAPHICS COMPILE PASS';return}
foreach($test in $tests) {
    $output=& (Join-Path $VivadoBin 'xsim.bat') $test.Snapshot '--nolog' '-runall' '-onfinish' 'quit' 2>&1 |
        Tee-Object -FilePath $test.Log
    $exitCode=$LASTEXITCODE
    $output | ForEach-Object {Write-Host $_}
    $joined=$output -join "`n"
    if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch $test.Marker) {throw "$($test.Snapshot) failed"}
}
Write-Host 'PTROCOS GRAPHICS TEST PASS'
