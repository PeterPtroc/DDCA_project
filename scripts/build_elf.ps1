#Requires -Version 5.1
<#
.SYNOPSIS
Build a standalone PtrocOS C application ELF for an SD card.
.DESCRIPTION
Uses the existing RISC-V toolchain, application CRT and linker script.
With no arguments, compiles the repository's demo.c into demo.elf beside it.
The C file must provide app_main using sw/ptrocos/elf/app_api.h.
Relative paths are resolved from the repository root. No firmware is built.
.EXAMPLE
.\scripts\build_elf.ps1
.EXAMPLE
.\scripts\build_elf.ps1 -Source D:\apps\demo.c -Output build\sd\DEMO.ELF
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Source = 'demo.c',
    [Parameter(Position = 1)]
    [string]$Output = 'demo.elf',
    [string]$ToolchainPrefix
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot

function Resolve-ProjectPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $Root $Path }
    return [IO.Path]::GetFullPath($Path)
}

function Find-Tool([string]$Suffix) {
    $candidate = "$ToolchainPrefix-$Suffix"
    $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw "RISC-V tool missing: $candidate"
}

$SourcePath = Resolve-ProjectPath $Source
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Application source not found: $SourcePath"
}
if ([IO.Path]::GetExtension($SourcePath) -ine '.c') {
    throw "Expected a single C source (.c): $SourcePath"
}
$Elf = Resolve-ProjectPath $Output
if ([IO.Path]::GetExtension($Elf) -ine '.elf') {
    throw "Output must have an .elf extension: $Elf"
}
$Map = [IO.Path]::ChangeExtension($Elf, '.map')
$Headers = [IO.Path]::ChangeExtension($Elf, '.headers.txt')

if (-not $ToolchainPrefix) { $ToolchainPrefix = $env:RISCV_TOOLCHAIN_PREFIX }
if (-not $ToolchainPrefix) { $ToolchainPrefix = & "$PSScriptRoot/setup_toolchain.ps1" }
if ($ToolchainPrefix -match '[/\\]') { $ToolchainPrefix = Resolve-ProjectPath $ToolchainPrefix }
$Gcc = Find-Tool 'gcc'
$Strip = Find-Tool 'strip'
$Readelf = Find-Tool 'readelf'

New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Elf)) -Force | Out-Null
$Flags = @('-march=rv32im', '-mabi=ilp32', '-mcmodel=medany', '-msmall-data-limit=0',
    '-mno-relax', '-Os', '-ffreestanding', '-fno-builtin', '-nostartfiles', '-nostdlib',
    '-Wall', '-Wextra', '-Werror', '-Wl,--no-relax', '-Wl,-z,max-page-size=4')
$Flags += @('-I', (Resolve-ProjectPath 'sw/ptrocos/elf'))
# Pass file paths separately so spaces and commas are preserved by GCC/ld.
$Flags += @('-T', (Resolve-ProjectPath 'sw/ptrocos/elf/app_linker.ld'),
    '-Xlinker', '-Map', '-Xlinker', $Map, (Resolve-ProjectPath 'sw/ptrocos/elf/app_crt.S'))
& $Gcc @Flags $SourcePath '-o' $Elf
if ($LASTEXITCODE -ne 0) { throw "Application build failed: $Elf (requires app_main and the PtrocOS application API)" }
& $Strip '--strip-all' $Elf
if ($LASTEXITCODE -ne 0) { throw "Application strip failed: $Elf" }
& $Readelf '-h' '-l' $Elf | Set-Content -LiteralPath $Headers -Encoding ascii
if ($LASTEXITCODE -ne 0) { throw "Application readelf failed: $Elf" }
Write-Host "APPLICATION ELF BUILD PASS: $Elf"
Write-Host ('Copy the ELF to the SD card, then use mount and run "/{0}" in PtrocOS.' -f [IO.Path]::GetFileName($Elf))
