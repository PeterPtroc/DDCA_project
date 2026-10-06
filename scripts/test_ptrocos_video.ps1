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
New-Item -ItemType Directory -Path build/ptrocos_video -Force | Out-Null
if($ToolchainPrefix) {
    if($RunOnly) {throw 'Build before RunOnly.'}
    & "$PSScriptRoot/build_ptrocos.ps1" -Firmware video -ToolchainPrefix $ToolchainPrefix
}
Invoke-Checked 'git' @('diff','--exit-code','--diff-filter=MDRT','80cc06f','--','src/rtl','scripts','constraints','sw/freertos')
$tests=@()
if(-not $SocOnly) {
    if(-not $RunOnly) {
        foreach($native in @('check_video_decode.py','check_video_player.py','check_video_commands.py','check_video_tools.py')) {
            Invoke-Checked 'python.exe' @("sw/tools/$native")
        }
        Invoke-Checked 'python.exe' @('sw/tools/gen_graphics_pattern.py')
        Invoke-Checked 'python.exe' @('sw/tools/gen_mono_pattern.py')
        $sources=@('src/rtl/memory/word_bus_cdc.v','src/rtl/memory/axi_read_arbiter.v',
            'src/rtl/video/vga_ddr_framebuffer.v','src/sim/axi_graphics_memory.sv','src/sim/tb_vga_ddr_framebuffer.sv')
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','video_unit')+$sources)
    }
    foreach($top in @('tb_vga_ddr_framebuffer','tb_vga_ddr_framebuffer_full','tb_vga_ddr_mono')) {
        if(-not $RunOnly) {
            Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"video_unit.$top",'-s',"${top}_video_sim",'--O3','-debug','off')
        }
        $tests+=[pscustomobject]@{Snapshot="${top}_video_sim";Marker='DDR FRAMEBUFFER UNIT PASS';Log="build/ptrocos_video/${top}.runtime.log"}
    }
}
if(-not $UnitOnly) {
    if(-not (Test-Path -LiteralPath build/hex/ptrocos_video.hex)) {throw 'Build video firmware first.'}
    if(-not $RunOnly) {
        Invoke-Checked 'python.exe' @('sw/tools/gen_video_image.py')
        $sources=@(Get-Content scripts/ptrocos_sources.txt)+@('src/sim/axi_graphics_memory.sv','src/sim/sd_spi_card_model.sv','src/sim/tb_ptrocos_video.sv')
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','video_soc')+$sources)
    }
    foreach($style in $PcStyle) {
        $top=if($style -eq 0) {'tb_ptrocos_video'} else {'tb_ptrocos_video_alt'}
        if(-not $RunOnly) {
            Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"video_soc.$top",'-s',"${top}_soc_sim",'--O3','-debug','off')
        }
        $tests+=[pscustomobject]@{Snapshot="${top}_soc_sim";Marker='PTROCOS VIDEO SOC PASS';Log="build/ptrocos_video/${top}.runtime.log"}
    }
}
if($CompileOnly) {Write-Host 'PTROCOS VIDEO COMPILE PASS';return}
foreach($test in $tests) {
    $output=& (Join-Path $VivadoBin 'xsim.bat') $test.Snapshot '--nolog' '-runall' '-onfinish' 'quit' 2>&1 | Tee-Object -FilePath $test.Log
    $exitCode=$LASTEXITCODE;$output | ForEach-Object {Write-Host $_};$joined=$output -join "`n"
    if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch $test.Marker) {throw "$($test.Snapshot) failed"}
}
Write-Host 'PTROCOS VIDEO TEST PASS'
