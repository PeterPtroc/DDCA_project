param([string]$VivadoBin='D:\xilinx\Vivado\2024.2\bin')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
Invoke-Checked 'python.exe' @('sw/tools/check_keyboard.py')
$sources=@('src/rtl/memory/word_bus_cdc.v','src/rtl/peripheral/ps2_keyboard.v',
    'src/rtl/video/text_font_rom.v','src/rtl/video/vga_text.v','src/sim/tb_ps2_keyboard.sv','src/sim/tb_vga_text.sv')
Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--nolog','--sv','-work','text_devices')+$sources)
foreach($top in @('tb_ps2_keyboard','tb_vga_text')) {
    $snapshot="${top}_sim"
    Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('--nolog','--timescale','1ns/1ps',"text_devices.$top",'-s',$snapshot,'-debug','typical')
    $output=& (Join-Path $VivadoBin 'xsim.bat') $snapshot '--nolog' '-runall' 2>&1
    $exitCode=$LASTEXITCODE
    $output | ForEach-Object {Write-Host $_}
    $marker=if($top -eq 'tb_ps2_keyboard') {'PS2 KEYBOARD PASS'} else {'VGA TEXT PASS'}
    if($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or ($output -join "`n") -notmatch $marker) {throw "$top failed"}
}
Write-Host 'TEXT DEVICES TEST PASS'
