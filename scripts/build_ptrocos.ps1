param([string]$ToolchainPrefix,[ValidateSet('ddr2','text','shell','storage','graphics','media','video','elf','perf')][string]$Firmware='ddr2')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
if(-not $ToolchainPrefix) {$ToolchainPrefix=$env:RISCV_TOOLCHAIN_PREFIX}
if(-not $ToolchainPrefix) {$ToolchainPrefix=& "$PSScriptRoot/setup_toolchain.ps1"}
function Find-Tool([string]$Suffix) {
    $candidate="$ToolchainPrefix-$Suffix"
    $command=Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($command) {return $command.Source}
    if(Test-Path -LiteralPath "$candidate.exe") {return (Resolve-Path -LiteralPath "$candidate.exe").Path}
    if(Test-Path -LiteralPath $candidate) {return (Resolve-Path -LiteralPath $candidate).Path}
    throw "RISC-V tool missing: $candidate"
}
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Command failed: $LASTEXITCODE"}
}
$Gcc=Find-Tool 'gcc';$Objcopy=Find-Tool 'objcopy';$Objdump=Find-Tool 'objdump';$Size=Find-Tool 'size'
$Python=(Get-Command python.exe -ErrorAction Stop).Source
$Out="build/ptrocos_$Firmware"
New-Item -ItemType Directory -Path $Out,'build/hex' -Force | Out-Null
$Flags=@('-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medany','-msmall-data-limit=0',
    '-O2','-g','-ffreestanding','-fno-builtin','-fdata-sections','-ffunction-sections','-Wall','-Wextra','-Werror','-Isw/ptrocos')
$Objects=@()
$Sources=@('sw/ptrocos/board.c',"sw/ptrocos/${Firmware}_main.c",'sw/ptrocos/os/runtime.c','sw/ptrocos/startup.S')
if($Firmware -eq 'text') {$Sources+=@('sw/ptrocos/keyboard.c','sw/ptrocos/text_console.c')}
if($Firmware -in @('shell','storage','graphics','media','video','elf')) {
    $Flags+=@('-Isw/ptrocos/os','-Ithird_party/freertos/kernel/include',
        '-Ithird_party/freertos/kernel/portable/GCC/RISC-V',
        '-Ithird_party/freertos/kernel/portable/GCC/RISC-V/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions')
    $Sources=@('sw/ptrocos/board.c','sw/ptrocos/shell_main.c','sw/ptrocos/tty.c',
        'sw/ptrocos/shell.c','sw/ptrocos/keyboard.c','sw/ptrocos/text_console.c','sw/ptrocos/string_runtime.c',
        'sw/ptrocos/os/runtime.c','sw/ptrocos/os/startup.S',
        'third_party/freertos/kernel/tasks.c','third_party/freertos/kernel/queue.c','third_party/freertos/kernel/list.c',
        'third_party/freertos/kernel/portable/MemMang/heap_4.c',
        'third_party/freertos/kernel/portable/GCC/RISC-V/port.c',
        'third_party/freertos/kernel/portable/GCC/RISC-V/portASM.S')
}
if($Firmware -in @('storage','graphics','media','video','elf')) {
    # Keep the complete exFAT shell within the existing 64 KiB ROM.
    $Flags=@($Flags | Where-Object {$_ -ne '-O2'})+@('-Os','-flto')
    $Flags+=@('-DPTROCOS_STORAGE','-Isw/ptrocos/storage','-Ithird_party/fatfs')
    $Sources+=@('sw/ptrocos/storage/sd_card.c','sw/ptrocos/storage/storage_disk.c',
        'sw/ptrocos/storage/storage_hw.c','sw/ptrocos/storage/storage_commands.c',
        'sw/ptrocos/storage/ff_port.c','third_party/fatfs/ff.c','third_party/fatfs/ffunicode.c')
}
if($Firmware -in @('graphics','media','video','elf')) {
    $Flags+=@('-DPTROCOS_GRAPHICS')
    $Sources+=@('sw/ptrocos/graphics.c')
}
if($Firmware -in @('media','video','elf')) {
    $Flags+=@('-DPTROCOS_MEDIA')
    $Sources+=@('sw/ptrocos/media/decode.c','sw/ptrocos/media/audio.c','sw/ptrocos/media/media_commands.c')
}
if($Firmware -in @('video','elf')) {
    $Flags+=@('-DPTROCOS_VIDEO')
    $Sources+=@('sw/ptrocos/media/video_decode.c','sw/ptrocos/media/video_player.c')
}
if($Firmware -eq 'elf') {
    & "$PSScriptRoot/build_ptrocos_apps.ps1" -ToolchainPrefix $ToolchainPrefix
    $Flags+=@('-DPTROCOS_ELF','-Ibuild/ptrocos_elf')
    $Sources+=@('sw/ptrocos/elf/elf_decode.c','sw/ptrocos/elf/elf_runtime.c','sw/ptrocos/elf/app_call.S')
}
foreach($source in $Sources) {
    $object=Join-Path $Out ((($source -replace '[/\\]','_') -replace '\.[cS]$','.o'))
    # Keep compiler-generated memcpy/memset calls backed by native symbols.
    $SourceFlags=if($source -eq 'sw/ptrocos/os/runtime.c') {@($Flags | Where-Object {$_ -ne '-flto'})} else {$Flags}
    Invoke-Checked $Gcc ($SourceFlags+@('-c',$source,'-o',$object))
    $Objects+=$object
}
$Elf="$Out/ptrocos_$Firmware.elf"
$LinkFlags=if($Firmware -in @('storage','graphics','media','video','elf')) {@('-Os','-flto')} else {@()}
Invoke-Checked $Gcc ($LinkFlags+@('-march=rv32im_zicsr','-mabi=ilp32','-nostartfiles','-nostdlib',
    '-Wl,-T,sw/ptrocos/linker.ld','-Wl,--gc-sections',"-Wl,-Map,$Out/ptrocos_$Firmware.map",'-o',$Elf)+$Objects+@('-lgcc'))
Invoke-Checked $Objcopy @('-O','binary',$Elf,"$Out/ptrocos_$Firmware.bin")
Invoke-Checked $Python @('sw/tools/bin2hex.py',"$Out/ptrocos_$Firmware.bin","build/hex/ptrocos_$Firmware.hex",'--limit','65536')
& $Objdump -d -S $Elf | Set-Content -LiteralPath "$Out/ptrocos_$Firmware.lst" -Encoding ascii
if($LASTEXITCODE -ne 0) {throw 'objdump failed'}
Invoke-Checked $Size @($Elf)
if($Firmware -eq 'elf') {Invoke-Checked $Python @('sw/tools/elf_call_reference.py','--toolchain-prefix',$ToolchainPrefix)}
Write-Host "PTROCOS BUILD PASS: build/hex/ptrocos_$Firmware.hex"
