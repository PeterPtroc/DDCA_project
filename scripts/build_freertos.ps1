# Compatibility entry for the unchanged README quick start.
param([string]$ToolchainPrefix)
$ErrorActionPreference='Stop'
& "$PSScriptRoot/build_ptrocos.ps1" -Firmware elf -ToolchainPrefix $ToolchainPrefix
Copy-Item -LiteralPath "$PSScriptRoot/../build/hex/ptrocos_elf.hex" -Destination "$PSScriptRoot/../build/hex/freertos.hex" -Force
Write-Host 'README QUICK START: PtrocOS ELF firmware built; freertos.hex is a compatibility copy.'
