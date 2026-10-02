param(
    [string]$VivadoBin
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

function Find-VivadoBin {
    if ($VivadoBin) {
        return (Resolve-Path -LiteralPath $VivadoBin).Path
    }

    $xvlog = Get-Command xvlog.bat -ErrorAction SilentlyContinue
    if ($xvlog) { return Split-Path -Parent $xvlog.Source }

    foreach ($vivadoRoot in @("D:\xilinx\Vivado", "C:\Xilinx\Vivado", "C:\AMD\Vivado")) {
        if (-not (Test-Path -LiteralPath $vivadoRoot)) { continue }
        foreach ($version in Get-ChildItem -LiteralPath $vivadoRoot -Directory |
            Sort-Object Name -Descending) {
            $bin = Join-Path $version.FullName "bin"
            if (Test-Path -LiteralPath (Join-Path $bin "xvlog.bat")) {
                return $bin
            }
        }
    }

    throw "Vivado XSim was not found. Pass -VivadoBin with the Vivado bin directory."
}

function Invoke-XSimTest {
    param([string]$Top, [string]$Testbench, [string]$ExpectedMarker)

    $snapshot = "${Top}_sim"
    $sources = @($script:RtlSources) + (Resolve-Path -LiteralPath $Testbench).Path
    Invoke-Checked $script:Xvlog (@("--nolog", "-work", "work") + $sources)
    Invoke-Checked $script:Xelab @("--nolog", $Top, "-s", $snapshot, "-debug", "typical")

    $output = & $script:Xsim $snapshot "--nolog" "-runall" 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "XSim test $Top failed with exit code $exitCode" }
    if (($output -join "`n") -notmatch [regex]::Escape($ExpectedMarker)) {
        throw "XSim test $Top did not emit: $ExpectedMarker"
    }
}

function Invoke-DifferentialTests {
    $snapshot = "tb_cpu_trace_sim"
    $testbench = (Resolve-Path -LiteralPath "src\sim\tb_cpu_trace.v").Path
    $sources = @($script:RtlSources) + $testbench
    Invoke-Checked $script:Xvlog (@("--nolog", "-work", "work") + $sources)
    Invoke-Checked $script:Xelab @("--nolog", "tb_cpu_trace", "-s", $snapshot, "-debug", "typical")

    New-Item -ItemType Directory -Path "build\trace" -Force | Out-Null
    New-Item -ItemType Directory -Path "build\benchmark" -Force | Out-Null
    foreach ($name in @("isa_test", "hazard_test", "crc_test")) {
        $referenceTrace = Join-Path "build\trace" "$name.reference.csv"
        $testFlag = $name.ToUpperInvariant()
        $output = & $script:Xsim $snapshot "--nolog" "--runall" `
            "--testplusarg" $testFlag 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if ($exitCode -ne 0 -or ($output -join "`n") -notmatch "RTL TRACE PASS") {
            throw "RTL trace simulation for $name failed"
        }
        Invoke-Checked $script:Python @(
            "sw\tools\rv32_ref.py", "build\hex\$name.hex", $referenceTrace
        )
        Invoke-Checked $script:Python @(
            "sw\tools\diff_trace.py", $referenceTrace,
            "build\trace\$name.rtl.csv", "--name", $name
        )
    }
}

$Python = (Get-Command python.exe -ErrorAction Stop).Source
$VivadoBin = Find-VivadoBin
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"

New-Item -ItemType Directory -Path "build\hex" -Force | Out-Null
foreach ($name in @("scope", "isa_test", "hazard_test", "crc_test")) {
    Invoke-Checked $Python @(
        "sw\tools\rv32asm.py", "sw\firmware\$name.S", "build\hex\$name.hex"
    )
}

Invoke-Checked $Python @("-m", "unittest", "discover", "-s", "sw\tools", "-p", "test_*.py")
Invoke-Checked $Python @("-m", "unittest", "discover", "-s", "tools", "-p", "test_*.py")

$RtlSources = @(
    "src\rtl\bus\mmio_decoder.v",
    "src\rtl\cpu\alu.v",
    "src\rtl\cpu\crc16_unit.v",
    "src\rtl\cpu\decoder.v",
    "src\rtl\cpu\forwarding_unit.v",
    "src\rtl\cpu\hazard_unit.v",
    "src\rtl\cpu\imm_gen.v",
    "src\rtl\cpu\regfile.v",
    "src\rtl\cpu\rv32_core.v",
    "src\rtl\memory\dmem.v",
    "src\rtl\memory\imem.v",
    "src\rtl\peripheral\button_debounce.v",
    "src\rtl\peripheral\button_mmio.v",
    "src\rtl\peripheral\edge_meter_scope.v",
    "src\rtl\peripheral\fixed_test_signals.v",
    "src\rtl\peripheral\gpio_mmio.v",
    "src\rtl\peripheral\input_sync.v",
    "src\rtl\peripheral\live_scope.v",
    "src\rtl\peripheral\perf_counter.v",
    "src\rtl\peripheral\rgb_status.v",
    "src\rtl\peripheral\scope_capture.v",
    "src\rtl\peripheral\sevenseg.v",
    "src\rtl\peripheral\timer_mmio.v",
    "src\rtl\peripheral\uart_mmio.v",
    "src\rtl\peripheral\uart_rx.v",
    "src\rtl\peripheral\uart_tx.v",
    "src\rtl\top\nexys_a7_top.v",
    "src\rtl\top\soc_top.v"
) | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }

Invoke-DifferentialTests
Invoke-XSimTest "tb_scope_core" "src\sim\tb_scope_core.v" "SCOPE CORE PASS"
Invoke-XSimTest "tb_soc_realtime_scope" "src\sim\tb_soc_realtime_scope.v" "SOC REALTIME SCOPE PASS"

Write-Host "COURSE DESIGN TEST PASS"
