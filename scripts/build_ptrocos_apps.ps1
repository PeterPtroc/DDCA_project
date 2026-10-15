param([string]$ToolchainPrefix)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
if(-not $ToolchainPrefix) {$ToolchainPrefix=$env:RISCV_TOOLCHAIN_PREFIX}
if(-not $ToolchainPrefix) {$ToolchainPrefix=& "$PSScriptRoot/setup_toolchain.ps1"}
$Readelf="$ToolchainPrefix-readelf.exe"
New-Item -ItemType Directory -Path build/ptrocos_elf/apps -Force | Out-Null
foreach($name in @('hello','fault','loop')) {
    $path="build/ptrocos_elf/apps/$name.elf"
    & "$PSScriptRoot/build_elf.ps1" -Source "sw/ptrocos/elf/$name.c" -Output $path -ToolchainPrefix $ToolchainPrefix
}
python.exe -E sw/tools/embed_ptrocos_apps.py
if($LASTEXITCODE -ne 0) {throw 'Application embedding failed'}
foreach($name in @('hello','fault','loop')) {
    & $Readelf '-h' '-l' "build/ptrocos_elf/apps/$name.elf" | Set-Content "build/ptrocos_elf/apps/$name.headers.txt" -Encoding ascii
    if($LASTEXITCODE -ne 0) {throw "Delivered application readelf failed: $name"}
}
Write-Host 'PTROCOS APPS BUILD PASS: hello fault loop'
