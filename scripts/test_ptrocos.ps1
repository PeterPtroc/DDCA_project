param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin',[string]$ToolchainPrefix,
    [ValidateSet('test','test_rv32m','test_memory_interface','test_ptrocos_app_memory',
        'test_ptrocos_ddr2','test_ptrocos_mig','test_text_devices','test_ptrocos_text',
        'test_ptrocos_shell','test_sd_spi','test_ptrocos_storage','test_ptrocos_files',
        'test_ptrocos_graphics','test_ptrocos_media','test_ptrocos_video','test_ptrocos_perf',
        'test_ptrocos_elf')][string]$ResumeFrom)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
$LogRoot='build/ptrocos-validation/cleanup'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
function Invoke-Stage([string]$Name,[string]$Script,[hashtable]$Parameters) {
    Write-Host "PTROCOS STAGE: $Name"
    if($Name -eq 'test_ptrocos_mig' -and -not (Test-Path -LiteralPath 'build/ptrocos_ddr2/ptrocos_ddr2.gen/sources_1/ip/ptrocos_ddr2_mig/ptrocos_ddr2_mig/user_design/rtl')) {
        & (Join-Path $VivadoBin 'vivado.bat') -mode batch -source scripts/create_ddr2_ip.tcl *> "$LogRoot/create_ddr2_ip.log"
        if($LASTEXITCODE -ne 0) {throw "MIG simulation model generation failed: $LASTEXITCODE"}
    }
    & $Script @Parameters *> "$LogRoot/$Name.log"
    Write-Host "PTROCOS STAGE PASS: $Name"
}
if(-not $ResumeFrom) {
foreach($firmware in @('ddr2','text','shell','storage','graphics','media','video','elf','perf')) {
    Invoke-Stage "build-$firmware" "$PSScriptRoot/build_ptrocos.ps1" @{Firmware=$firmware;ToolchainPrefix=$ToolchainPrefix}
}
foreach($name in @('check_sd_card','check_fatfs','check_storage_commands',
    'check_storage_uart_tool','check_elf_decode','check_elf_storage')) {
    Write-Host "PTROCOS STAGE: $name"
    & python.exe "sw/tools/$name.py" *> "$LogRoot/$name.log"
    if($LASTEXITCODE -ne 0) {throw "$name failed: $LASTEXITCODE"}
    Write-Host "PTROCOS STAGE PASS: $name"
}
}
$RunStage=-not $ResumeFrom
foreach($name in @('test','test_rv32m','test_memory_interface','test_ptrocos_app_memory',
    'test_ptrocos_ddr2','test_ptrocos_mig','test_text_devices','test_ptrocos_text',
    'test_ptrocos_shell','test_sd_spi','test_ptrocos_storage','test_ptrocos_files',
    'test_ptrocos_graphics','test_ptrocos_media','test_ptrocos_video','test_ptrocos_perf')) {
    if($name -eq $ResumeFrom) {$RunStage=$true}
    if($RunStage) {Invoke-Stage $name "$PSScriptRoot/$name.ps1" @{VivadoBin=$VivadoBin}}
}
Invoke-Stage 'test_ptrocos_elf' "$PSScriptRoot/test_ptrocos_elf.ps1" @{VivadoBin=$VivadoBin;VideoRegression=$true}
if($ResumeFrom) {Write-Host "PTROCOS RESUMED REGRESSION PASS from=$ResumeFrom : $LogRoot"}
else {Write-Host "PTROCOS FULL REGRESSION PASS: $LogRoot"}
