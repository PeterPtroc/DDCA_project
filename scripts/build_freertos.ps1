param(
    [string]$ToolchainPrefix
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

function Find-Tool {
    param([string]$Suffix)
    $candidate = "$ToolchainPrefix-$Suffix"
    $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    if (Test-Path -LiteralPath "$candidate.exe" -PathType Leaf) {
        return (Resolve-Path -LiteralPath "$candidate.exe").Path
    }
    throw "RISC-V tool not found: $candidate. Check -ToolchainPrefix or RISCV_TOOLCHAIN_PREFIX."
}

$PythonCommand = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $PythonCommand) {
    throw "Python 3 is required to generate the firmware HEX. Install Python 3 and add python.exe to PATH."
}
$Python = $PythonCommand.Source
if (-not $ToolchainPrefix) { $ToolchainPrefix = $env:RISCV_TOOLCHAIN_PREFIX }
if (-not $ToolchainPrefix) { $ToolchainPrefix = & "$PSScriptRoot\setup_toolchain.ps1" }

$Gcc = Find-Tool "gcc"
$Objcopy = Find-Tool "objcopy"
$Objdump = Find-Tool "objdump"
$Size = Find-Tool "size"

$Out = Join-Path $Root "build\freertos"
$HexDir = Join-Path $Root "build\hex"
New-Item -ItemType Directory -Force -Path $Out, $HexDir | Out-Null

$Includes = @(
    "-Isw/freertos",
    "-Isw/freertos/kernel/include",
    "-Isw/freertos/kernel/portable/GCC/RISC-V",
    "-Isw/freertos/kernel/portable/GCC/RISC-V/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions"
)
$Common = @(
    "-march=rv32i_zicsr", "-mabi=ilp32", "-mcmodel=medany", "-msmall-data-limit=0",
    "-O2", "-g", "-ffreestanding", "-fno-builtin", "-fdata-sections",
    "-ffunction-sections", "-Wall", "-Wextra", "-Wno-unused-parameter"
) + $Includes

$Sources = @(
    "sw/freertos/main.c",
    "sw/freertos/board.c",
    "sw/freertos/runtime.c",
    "sw/freertos/kernel/tasks.c",
    "sw/freertos/kernel/queue.c",
    "sw/freertos/kernel/list.c",
    "sw/freertos/kernel/portable/MemMang/heap_4.c",
    "sw/freertos/kernel/portable/GCC/RISC-V/port.c"
)
$Objects = @()
foreach ($source in $Sources) {
    $name = ($source -replace '[/\\]', '_') -replace '\.c$', '.o'
    $object = Join-Path $Out $name
    Invoke-Checked $Gcc ($Common + @("-std=c11", "-c", $source, "-o", $object))
    $Objects += $object
}

foreach ($source in @(
    "sw/freertos/startup.S",
    "sw/freertos/kernel/portable/GCC/RISC-V/portASM.S"
)) {
    $name = ($source -replace '[/\\]', '_') -replace '\.S$', '.o'
    $object = Join-Path $Out $name
    Invoke-Checked $Gcc ($Common + @("-x", "assembler-with-cpp", "-c", $source, "-o", $object))
    $Objects += $object
}

$Elf = Join-Path $Out "freertos.elf"
$Map = Join-Path $Out "freertos.map"
$Binary = Join-Path $Out "freertos.bin"
$Listing = Join-Path $Out "freertos.lst"
$Hex = Join-Path $HexDir "freertos.hex"
$LinkFlags = @(
    "-march=rv32i_zicsr", "-mabi=ilp32", "-nostartfiles", "-nostdlib",
    "-Wl,-T,sw/freertos/linker.ld", "-Wl,--gc-sections", "-Wl,-Map,$Map",
    "-o", $Elf
)
Invoke-Checked $Gcc ($LinkFlags + $Objects + @("-Wl,--start-group", "-lgcc", "-Wl,--end-group"))
Invoke-Checked $Objcopy @("-O", "binary", $Elf, $Binary)
Invoke-Checked $Python @("sw/tools/bin2hex.py", $Binary, $Hex, "--limit", "65536")
& $Objdump -d -S $Elf | Set-Content -LiteralPath $Listing -Encoding ascii
Invoke-Checked $Size @($Elf)
Write-Host "FREERTOS BUILD PASS: $Hex"

