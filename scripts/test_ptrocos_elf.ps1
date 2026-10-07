param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix,
    [ValidateSet(0,1)][int[]]$PcStyle=@(0,1),[switch]$CompileOnly,[switch]$RunOnly,[switch]$NativeOnly,[switch]$VideoRegression)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
if(($CompileOnly -and $RunOnly) -or ($NativeOnly -and ($CompileOnly -or $RunOnly -or $VideoRegression))) {throw 'Incompatible switches'}
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
New-Item -ItemType Directory -Path build/ptrocos_elf -Force | Out-Null
if($ToolchainPrefix) {
    if($RunOnly) {throw 'Build before RunOnly'}
    & "$PSScriptRoot/build_ptrocos.ps1" -Firmware elf -ToolchainPrefix $ToolchainPrefix
}
if(-not (Test-Path -LiteralPath build/hex/ptrocos_elf.hex)) {throw 'Build ELF firmware first'}
if($NativeOnly) {
    Invoke-Checked 'python.exe' @('sw/tools/check_elf_decode.py')
    Invoke-Checked 'python.exe' @('sw/tools/check_elf_storage.py')
    Write-Host 'PTROCOS ELF NATIVE PASS';return
}
if(-not $RunOnly) {
    Invoke-Checked 'python.exe' @('sw/tools/elf_fixture.py')
    $sources=@(Get-Content scripts/ptrocos_elf_sources.txt)+@('src/sim/axi_sparse_memory.sv','src/sim/sd_spi_card_model.sv','src/sim/tb_ptrocos_elf.sv')
    Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','elf_soc')+$sources)
    foreach($style in $PcStyle) {
        $top=if($style -eq 0) {'tb_ptrocos_elf'} else {'tb_ptrocos_elf_alt'}
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"elf_soc.$top",'-s',"${top}_sim",'--O3','-debug','off')
    }
    if($VideoRegression) {
        Invoke-Checked 'python.exe' @('sw/tools/gen_video_image.py')
        $sources=@(Get-Content scripts/ptrocos_elf_sources.txt)+@('src/sim/axi_graphics_memory.sv','src/sim/sd_spi_card_model.sv','src/sim/tb_ptrocos_elf_video.sv')
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','elf_video')+$sources)
        foreach($style in $PcStyle) {
            $top=if($style -eq 0) {'tb_ptrocos_elf_video'} else {'tb_ptrocos_elf_video_alt'}
            Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"elf_video.$top",'-s',"${top}_sim",'--O3','-debug','off')
        }
    }
}
if($CompileOnly) {Write-Host 'PTROCOS ELF COMPILE PASS';return}
foreach($style in $PcStyle) {
    $top=if($style -eq 0) {'tb_ptrocos_elf'} else {'tb_ptrocos_elf_alt'}
    $output=& (Join-Path $VivadoBin 'xsim.bat') "${top}_sim" '--nolog' '-runall' '-onfinish' 'quit' 2>&1
    $exitCode=$LASTEXITCODE
    $output | Set-Content -LiteralPath "build/ptrocos_elf/runtime.style$style.log" -Encoding utf8
    $output | ForEach-Object {Write-Host $_}
    $joined=$output -join "`n"
    if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch "PTROCOS ELF SOC PASS style=$style") {throw "ELF style $style failed"}
}
if($VideoRegression) {
    foreach($style in $PcStyle) {
        $top=if($style -eq 0) {'tb_ptrocos_elf_video'} else {'tb_ptrocos_elf_video_alt'}
        $output=& (Join-Path $VivadoBin 'xsim.bat') "${top}_sim" '--nolog' '-runall' '-onfinish' 'quit' 2>&1
        $exitCode=$LASTEXITCODE
        $output | Set-Content -LiteralPath "build/ptrocos_elf/video-runtime.style$style.log" -Encoding utf8
        $output | ForEach-Object {Write-Host $_};$joined=$output -join "`n"
        if($exitCode -ne 0 -or $joined -match 'Fatal:|FATAL_ERROR' -or $joined -notmatch "PTROCOS ELF VIDEO SOC PASS style=$style") {throw "ELF video style $style failed"}
    }
}
Write-Host 'PTROCOS ELF TEST PASS'
