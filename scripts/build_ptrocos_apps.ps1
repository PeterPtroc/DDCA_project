param([string]$ToolchainPrefix)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
if(-not $ToolchainPrefix) {$ToolchainPrefix=$env:RISCV_TOOLCHAIN_PREFIX}
if(-not $ToolchainPrefix) {$ToolchainPrefix=& "$PSScriptRoot/setup_toolchain.ps1"}
$Gcc="$ToolchainPrefix-gcc.exe";$Strip="$ToolchainPrefix-strip.exe";$Readelf="$ToolchainPrefix-readelf.exe"
New-Item -ItemType Directory -Path build/ptrocos_elf/apps -Force | Out-Null
foreach($name in @('hello','fault','loop')) {
    $path="build/ptrocos_elf/apps/$name.elf"
    & $Gcc '-march=rv32im' '-mabi=ilp32' '-mcmodel=medany' '-msmall-data-limit=0' '-mno-relax' '-Os' '-ffreestanding' '-fno-builtin' '-nostartfiles' '-nostdlib' '-Wall' '-Wextra' '-Werror' '-Isw/ptrocos/elf' '-Wl,--no-relax' '-Wl,-z,max-page-size=4' '-Wl,-T,sw/ptrocos/elf/app_linker.ld' "-Wl,-Map,build/ptrocos_elf/apps/$name.map" 'sw/ptrocos/elf/app_crt.S' "sw/ptrocos/elf/$name.c" '-o' $path
    if($LASTEXITCODE -ne 0) {throw "Application build failed: $name"}
    & $Strip '--strip-all' $path
    if($LASTEXITCODE -ne 0) {throw "Application strip failed: $name"}
    & $Readelf '-h' '-l' $path | Set-Content "build/ptrocos_elf/apps/$name.headers.txt" -Encoding ascii
    if($LASTEXITCODE -ne 0) {throw "Application readelf failed: $name"}
}
python.exe sw/tools/embed_ptrocos_apps.py
if($LASTEXITCODE -ne 0) {throw 'Application embedding failed'}
foreach($name in @('hello','fault','loop')) {
    & $Readelf '-h' '-l' "build/ptrocos_elf/apps/$name.elf" | Set-Content "build/ptrocos_elf/apps/$name.headers.txt" -Encoding ascii
    if($LASTEXITCODE -ne 0) {throw "Delivered application readelf failed: $name"}
}
Write-Host 'PTROCOS APPS BUILD PASS: hello fault loop'
