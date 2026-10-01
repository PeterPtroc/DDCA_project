param(
    [string]$Port = "COM9",
    [switch]$RequireSelfTest,
    [string]$ArtifactDirectory = "build\hardware"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Read-Exact {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$Count,
        [string]$Stage
    )
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
    try {
        $status = $serial.ReadLine().Trim()
    }
    catch {
        throw "UART timeout during status response: $($_.Exception.Message)"
    }
    if (-not $status.StartsWith("SCP2")) {
        throw "Unexpected status response: $status"
    }
    if ($RequireSelfTest -and $status -ne "SCP2 SELFTEST PASS") {
        throw "Physical self-test is required: set SW14=1 and check JA1->JB1 (status='$status')"
    }

    $serial.Write("m")
    $measurement = Read-Exact $serial 24 "measurement response"
    $measurementMagic = [Text.Encoding]::ASCII.GetString($measurement, 0, 4)
    $flags = [BitConverter]::ToUInt32($measurement, 4)
    $frequency = [BitConverter]::ToUInt32($measurement, 8)
    $period = [BitConverter]::ToUInt32($measurement, 12)
    $high = [BitConverter]::ToUInt32($measurement, 16)
    $low = [BitConverter]::ToUInt32($measurement, 20)
    if ($measurementMagic -ne "MEA2" -or ($flags -band 3) -ne 3) {
        throw "No valid physical signal: magic=$measurementMagic flags=$flags"
    }
    if ([math]::Abs([int64]$frequency - 100000) -gt 200 -or
        [math]::Abs([int64]$period - 1000) -gt 2 -or
        [math]::Abs([int64]$high - 300) -gt 2 -or
        [math]::Abs([int64]$low - 700) -gt 2) {
        throw "Expected SW[7:4]=9 and SW[11:8]=4 (100 kHz/30%): frequency=$frequency period=$period high=$high low=$low"
    }

    $serial.Write("d")
    $capture = Read-Exact $serial 540 "capture response"
    $captureMagic = [Text.Encoding]::ASCII.GetString($capture, 0, 4)
    $version = $capture[4]
    $count = [BitConverter]::ToUInt16($capture, 6)
    $sampleDiv = [BitConverter]::ToUInt32($capture, 8)
    $triggerIndex = [BitConverter]::ToUInt16($capture, 12)
    if ($captureMagic -ne "CAP2" -or $version -ne 2 -or $count -ne 4096 -or
        $triggerIndex -ne 2048 -or $sampleDiv -lt 1) {
        throw "Capture header mismatch: magic=$captureMagic version=$version count=$count div=$sampleDiv trigger=$triggerIndex"
    }
    $expectedCrc = [BitConverter]::ToUInt16($capture, 538)
    $actualCrc = Get-Crc16Modbus $capture 538
    if ($expectedCrc -ne $actualCrc) {
        throw ("Capture CRC mismatch: received=0x{0:x4} calculated=0x{1:x4}" -f $expectedCrc, $actualCrc)
    }

    $ones = 0
    for ($sample = 0; $sample -lt 4096; $sample++) {
        $packed = $capture[26 + ($sample -shr 3)]
        $ones += ($packed -shr ($sample -band 7)) -band 1
    }
    if ($ones -eq 0 -or $ones -eq 4096) {
        throw "Packed capture is constant: ones=$ones"
    }

    $serial.Write("p")
    $performance = Read-Exact $serial 40 "performance response"
    $performanceMagic = [Text.Encoding]::ASCII.GetString($performance, 0, 4)
    $crcInstructions = [BitConverter]::ToUInt32($performance, 36)
    if ($performanceMagic -ne "PRF2" -or $crcInstructions -lt 538) {
        throw "Performance response mismatch: magic=$performanceMagic crc_instructions=$crcInstructions"
    }

    $root = Split-Path -Parent $PSScriptRoot
    $artifactRoot = Join-Path $root $ArtifactDirectory
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    $packetPath = Join-Path $artifactRoot "physical_100khz_30pct.cap2"
    $csvPath = Join-Path $artifactRoot "physical_100khz_30pct.csv"
    $vcdPath = Join-Path $artifactRoot "physical_100khz_30pct.vcd"
    [IO.File]::WriteAllBytes($packetPath, [byte[]]$capture)

    $python = (Get-Command python.exe -ErrorAction Stop).Source
    & $python (Join-Path $root "tools\capture_dump.py") $packetPath $vcdPath --csv $csvPath
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $csvPath) -or
        -not (Test-Path -LiteralPath $vcdPath)) {
        throw "Physical CAP2 CSV/VCD export failed"
    }

    $duty = [math]::Round(100.0 * $high / $period, 3)
    Write-Host "HARDWARE SCOPE PASS: status='$status' frequency=${frequency}Hz period=$period high=$high low=$low duty=$duty% samples=$count packed=512 CRC=0x$($actualCrc.ToString('x4')) ones=$ones crc_instructions=$crcInstructions artifacts='$artifactRoot'"
}
finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
