param(
    [string]$Port = "COM9",
    [switch]$OptionalDump,
    [string]$ArtifactDirectory = "build\hardware",
    [ValidateSet("JA1", "JA2", "JA3", "JA4", "JA7", "JA8", "JA9", "JA10")]
    [string]$ExpectedOutput = "JA9"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$expectedSignals = @{
    JA1  = @{ Frequency = 1000;   Period = 100000; High = 20000 }
    JA2  = @{ Frequency = 2000;   Period = 50000;  High = 15000 }
    JA3  = @{ Frequency = 5000;   Period = 20000;  High = 8000 }
    JA4  = @{ Frequency = 14243;  Period = 7021;   High = 3511 }
    JA7  = @{ Frequency = 20000;  Period = 5000;   High = 3000 }
    JA8  = @{ Frequency = 50000;  Period = 2000;   High = 1400 }
    JA9  = @{ Frequency = 100000; Period = 1000;   High = 800 }
    JA10 = @{ Frequency = 200000; Period = 500;    High = 450 }
}
$expected = $expectedSignals[$ExpectedOutput]

function Read-Exact {
    param([System.IO.Ports.SerialPort]$Serial, [int]$Count, [string]$Stage)
    $buffer = [byte[]]::new($Count)
    $received = 0
    while ($received -lt $Count) {
        try {
            $received += $Serial.Read($buffer, $received, $Count - $received)
        }
        catch {
            throw "UART timeout during $Stage after $received/$Count bytes: $($_.Exception.Message)"
        }
    }
    return $buffer
}

function Get-Crc16Modbus {
    param([byte[]]$Data, [int]$Count)
    [uint16]$crc = 0xffff
    for ($index = 0; $index -lt $Count; $index++) {
        $crc = [uint16]($crc -bxor $Data[$index])
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 1) -ne 0) {
                $crc = [uint16](($crc -shr 1) -bxor 0xa001)
            }
            else {
                $crc = [uint16]($crc -shr 1)
            }
        }
    }
    return $crc
}

$serial = [System.IO.Ports.SerialPort]::new(
    $Port, 115200, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One
)
$serial.ReadTimeout = 15000
$serial.WriteTimeout = 3000

try {
    $serial.Open()
    Start-Sleep -Milliseconds 1200
    $serial.DiscardInBuffer()

    $serial.Write("s")
    try { $status = $serial.ReadLine().Trim() }
    catch { throw "UART timeout during status response: $($_.Exception.Message)" }
    if ($status -ne "SCP2") {
        throw "Unexpected status response '$status'"
    }

    $serial.Write("m")
    $measurement = Read-Exact $serial 24 "measurement response"
    $magic = [Text.Encoding]::ASCII.GetString($measurement, 0, 4)
    $flags = [BitConverter]::ToUInt32($measurement, 4)
    $frequency = [BitConverter]::ToUInt32($measurement, 8)
    $period = [BitConverter]::ToUInt32($measurement, 12)
    $high = [BitConverter]::ToUInt32($measurement, 16)
    $low = [BitConverter]::ToUInt32($measurement, 20)
    if ($magic -ne "MEA2" -or ($flags -band 3) -ne 3) {
        throw "No valid physical signal: magic=$magic flags=$flags"
    }
    $expectedLow = $expected.Period - $expected.High
    $frequencyTolerance = [math]::Max(2, [math]::Ceiling($expected.Frequency * 0.002))
    if ([math]::Abs([int64]$frequency - $expected.Frequency) -gt $frequencyTolerance -or
        [math]::Abs([int64]$period - $expected.Period) -gt 2 -or
        [math]::Abs([int64]$high - $expected.High) -gt 2 -or
        [math]::Abs([int64]$low - $expectedLow) -gt 2) {
        throw "Expected $ExpectedOutput signal: frequency=$frequency period=$period high=$high low=$low"
    }

    $serial.Write("p")
    $performance = Read-Exact $serial 40 "performance response"
    $performanceMagic = [Text.Encoding]::ASCII.GetString($performance, 0, 4)
    $cycleCount = [BitConverter]::ToUInt32($performance, 4)
    $retireCount = [BitConverter]::ToUInt32($performance, 8)
    if ($performanceMagic -ne "PRF2" -or $cycleCount -eq 0 -or $retireCount -eq 0) {
        throw "Performance response mismatch"
    }

    $dumpSummary = " cycle=$cycleCount instret=$retireCount"
    if ($OptionalDump) {
        $serial.Write("d")
        $capture = Read-Exact $serial 540 "capture response"
        $captureMagic = [Text.Encoding]::ASCII.GetString($capture, 0, 4)
        $version = $capture[4]
        $count = [BitConverter]::ToUInt16($capture, 6)
        $sampleDiv = [BitConverter]::ToUInt32($capture, 8)
        $triggerIndex = [BitConverter]::ToUInt16($capture, 12)
        if ($captureMagic -ne "CAP2" -or $version -ne 2 -or $count -ne 4096 -or
            $triggerIndex -ne 2048 -or $sampleDiv -lt 1) {
            throw "Capture header mismatch"
        }
        $expectedCrc = [BitConverter]::ToUInt16($capture, 538)
        $actualCrc = Get-Crc16Modbus $capture 538
        if ($expectedCrc -ne $actualCrc) { throw "Capture CRC mismatch" }

        $root = Split-Path -Parent $PSScriptRoot
        $artifactRoot = Join-Path $root $ArtifactDirectory
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
        $artifactStem = "physical_$($ExpectedOutput.ToLowerInvariant())"
        $packetPath = Join-Path $artifactRoot "$artifactStem.cap2"
        $csvPath = Join-Path $artifactRoot "$artifactStem.csv"
        $vcdPath = Join-Path $artifactRoot "$artifactStem.vcd"
        [IO.File]::WriteAllBytes($packetPath, [byte[]]$capture)
        $python = (Get-Command python.exe -ErrorAction Stop).Source
        & $python (Join-Path $root "tools\capture_dump.py") $packetPath $vcdPath --csv $csvPath
        if ($LASTEXITCODE -ne 0) { throw "CAP2 CSV/VCD export failed" }

        $serial.Write("p")
        $performanceAfterDump = Read-Exact $serial 40 "performance response after capture"
        $performanceMagic = [Text.Encoding]::ASCII.GetString($performanceAfterDump, 0, 4)
        $crcInstructions = [BitConverter]::ToUInt32($performanceAfterDump, 36)
        if ($performanceMagic -ne "PRF2" -or $crcInstructions -lt 538) {
            throw "Performance response mismatch"
        }
        $dumpSummary += " CAP2=PASS CRC=0x$($actualCrc.ToString('x4')) crc_instructions=$crcInstructions"
    }

    $duty = [math]::Round(100.0 * $high / $period, 3)
    Write-Host "HARDWARE SCOPE PASS ($ExpectedOutput -> JB1): status='$status' frequency=${frequency}Hz period=$period high=$high low=$low duty=$duty%$dumpSummary"
}
finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
