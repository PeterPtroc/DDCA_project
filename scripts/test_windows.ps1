param(
    [string]$VivadoBin
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

function Invoke-Checked {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

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
    if ($xvlog) {
        return Split-Path -Parent $xvlog.Source
    }

    $roots = @(
        "D:\xilinx\Vivado",
        "C:\Xilinx\Vivado",
        "C:\AMD\Vivado"
    )
    foreach ($vivadoRoot in $roots) {
        if (-not (Test-Path -LiteralPath $vivadoRoot)) {
            continue
        }
        $versions = Get-ChildItem -LiteralPath $vivadoRoot -Directory |
            Sort-Object Name -Descending
        foreach ($version in $versions) {
            $bin = Join-Path $version.FullName "bin"
            if (Test-Path -LiteralPath (Join-Path $bin "xvlog.bat")) {
                return $bin
            }
        }
    }

    throw "Vivado XSim was not found. Pass -VivadoBin with the Vivado bin directory."
}

function Invoke-XSimTest {
    param(
        [string]$Top,
        [string]$Testbench,
        [string]$ExpectedMarker
    )

    $snapshot = "${Top}_sim"
    $sources = @($script:RtlSources) + (Resolve-Path -LiteralPath $Testbench).Path
    Invoke-Checked $script:Xvlog (@("--nolog", "-work", "work") + $sources)
    Invoke-Checked $script:Xelab @("--nolog", $Top, "-s", $snapshot, "-debug", "typical")

    $output = & $script:Xsim $snapshot "--nolog" "-runall" 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) {
        throw "XSim test $Top failed with exit code $exitCode"
    }
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
    foreach ($name in @("isa_test", "hazard_test", "crc_test")) {
        $referenceTrace = Join-Path "build\trace" "$name.reference.csv"
        $testFlag = $name.ToUpperInvariant()

        $output = & $script:Xsim $snapshot "--nolog" "--runall" `
            "--testplusarg" $testFlag 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if ($exitCode -ne 0) {
            throw "RTL trace simulation for $name failed with exit code $exitCode"
        }
        if (($output -join "`n") -notmatch "RTL TRACE PASS") {
            throw "RTL trace simulation for $name did not report PASS"
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

Write-Host "Python: $Python"
Write-Host "Vivado bin: $VivadoBin"

New-Item -ItemType Directory -Path "build\hex" -Force | Out-Null
foreach ($firmware in Get-ChildItem -LiteralPath "sw\firmware" -Filter "*.S") {
    $output = Join-Path "build\hex" ($firmware.BaseName + ".hex")
    Invoke-Checked $Python @("sw\tools\rv32asm.py", $firmware.FullName, $output)
}

Invoke-Checked $Python @("-m", "unittest", "discover", "-s", "sw\tools", "-p", "test_*.py")
Invoke-Checked $Python @("-m", "unittest", "discover", "-s", "tools", "-p", "test_*.py")

$RtlSources = @(
    Get-ChildItem -LiteralPath "src\rtl" -Filter "*.v" -Recurse |
        Sort-Object FullName |
        ForEach-Object FullName
)

Invoke-DifferentialTests
Invoke-XSimTest "tb_mmio_map" "src\sim\tb_mmio_map.v" "MMIO MAP PASS"
Invoke-XSimTest "tb_analyzer_peripherals" "src\sim\tb_analyzer_peripherals.v" "ANALYZER PERIPHERALS PASS"
Invoke-XSimTest "tb_logic_capture_v1" "src\sim\tb_logic_capture_v1.v" "LOGIC CAPTURE V1 PASS"
Invoke-XSimTest "tb_live_scope" "src\sim\tb_live_scope.v" "LIVE SCOPE PASS"
Invoke-XSimTest "tb_edge_meter_scope" "src\sim\tb_edge_meter_scope.v" "EDGE METER SCOPE PASS"
Invoke-XSimTest "tb_signal_generator" "src\sim\tb_signal_generator.v" "SIGNAL GENERATOR PASS"
Invoke-XSimTest "tb_scope_capture" "src\sim\tb_scope_capture.v" "SCOPE CAPTURE PASS"
Invoke-XSimTest "tb_scope_ui" "src\sim\tb_scope_ui.v" "SCOPE UI PASS"
Invoke-XSimTest "tb_soc_mvp" "src\sim\tb_soc_mvp.v" "MVP PASS"
Invoke-XSimTest "tb_soc_analyzer" "src\sim\tb_soc_analyzer.v" "SOC ANALYZER PASS"
Invoke-XSimTest "tb_soc_realtime_scope" "src\sim\tb_soc_realtime_scope.v" "SOC REALTIME SCOPE PASS"

Write-Host "WINDOWS TEST PASS"
