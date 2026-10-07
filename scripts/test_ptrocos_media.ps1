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
New-Item -ItemType Directory -Path 'build/ptrocos_media' -Force | Out-Null
if($ToolchainPrefix) {
    if($RunOnly) {throw 'Build before RunOnly.'}
    & "$PSScriptRoot/build_ptrocos.ps1" -Firmware media -ToolchainPrefix $ToolchainPrefix
}
$tests=@()
if(-not $SocOnly) {
    if(-not $RunOnly) {
        Invoke-Checked 'python.exe' @('sw/tools/check_media_decode.py')
        Invoke-Checked 'python.exe' @('sw/tools/check_media_commands.py')
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') @('--nolog','--sv','-work','audio_unit','src/rtl/peripheral/pcm_audio.v','src/sim/tb_pcm_audio.sv')
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps','audio_unit.tb_pcm_audio','-s','tb_pcm_audio_unit_sim','-debug','typical')
    }
    $tests+=[pscustomobject]@{Snapshot='tb_pcm_audio_unit_sim';Marker='PCM AUDIO UNIT PASS';Log='build/ptrocos_media/audio.runtime.log'}
}
if(-not $UnitOnly) {
    if(-not (Test-Path -LiteralPath 'build/hex/ptrocos_media.hex')) {throw 'Build media firmware first.'}
    if(-not $RunOnly) {
        Invoke-Checked 'python.exe' @('sw/tools/gen_media_image.py')
        $sources=@(Get-Content 'scripts/ptrocos_sources.txt')+@('src/sim/axi_graphics_memory.sv','src/sim/sd_spi_card_model.sv','src/sim/tb_ptrocos_media.sv')
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','media_soc')+$sources)
    }
    foreach($style in $PcStyle) {
        $top=if($style -eq 0) {'tb_ptrocos_media'} else {'tb_ptrocos_media_alt'}
        if(-not $RunOnly) {Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"media_soc.$top",'-s',"${top}_soc_sim",'-debug','typical')}
        $tests+=[pscustomobject]@{Snapshot="${top}_soc_sim";Marker='PTROCOS MEDIA SOC PASS';Log="build/ptrocos_media/${top}.runtime.log"}
    }
}
if($CompileOnly) {Write-Host 'PTROCOS MEDIA COMPILE PASS';return}
foreach($test in $tests) {
    $output=& (Join-Path $VivadoBin 'xsim.bat') $test.Snapshot '--nolog' '-runall' '-onfinish' 'quit' 2>&1 | Tee-Object -FilePath $test.Log
    $exitCode=$LASTEXITCODE;$output | ForEach-Object {Write-Host $_};$joined=$output -join "`n"
    if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch $test.Marker) {throw "$($test.Snapshot) failed"}
}
Write-Host 'PTROCOS MEDIA TEST PASS'
