param(
    [string]$Port = "COM9"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Read-Exact {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$Count
    )

    $buffer = [byte[]]::new($Count)
    $received = 0
    while ($received -lt $Count) {
        $received += $Serial.Read($buffer, $received, $Count - $received)
    }
    return $buffer
}

$serial = [System.IO.Ports.SerialPort]::new(
    $Port, 115200, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One
)
$serial.ReadTimeout = 8000
$serial.WriteTimeout = 3000

try {
    $serial.Open()
    $serial.DiscardInBuffer()

    $serial.Write("s")
    $status = $serial.ReadLine().Trim()
    if ($status -ne "RV32 ANALYZER READY") {
        throw "Unexpected status response: $status"
    }

    $serial.Write("m")
    $measurement = Read-Exact $serial 16
    $measurementMagic = [Text.Encoding]::ASCII.GetString($measurement, 0, 4)
    $frequency = [BitConverter]::ToUInt32($measurement, 4)
    $period = [BitConverter]::ToUInt32($measurement, 8)
    $high = [BitConverter]::ToUInt32($measurement, 12)
    if ($measurementMagic -ne "MEA0" -or $frequency -ne 390625 -or
        $period -ne 256 -or $high -ne 77) {
        throw "Measurement mismatch: magic=$measurementMagic frequency=$frequency period=$period high=$high"
    }

    $serial.Write("d")
    $capture = Read-Exact $serial 4102
    $captureMagic = [Text.Encoding]::ASCII.GetString($capture, 0, 4)
    $count = [BitConverter]::ToUInt16($capture, 4)
    if ($captureMagic -ne "CAP0" -or $count -ne 4096) {
        throw "Capture header mismatch: magic=$captureMagic count=$count"
    }

    $rises = [System.Collections.Generic.List[int]]::new()
    $highSamples = 0
    for ($index = 0; $index -lt $count; $index++) {
        $sample = $capture[6 + $index]
        if (($sample -band 1) -ne 0) {
            $highSamples++
        }
        if ($index -gt 0 -and (($capture[5 + $index] -band 1) -eq 0) -and
            (($sample -band 1) -ne 0)) {
            $rises.Add($index)
        }
    }
    if ($rises.Count -lt 10) {
        throw "Capture contains only $($rises.Count) rising edges"
    }
    for ($index = 1; $index -lt $rises.Count; $index++) {
        $measuredPeriod = $rises[$index] - $rises[$index - 1]
        if ($measuredPeriod -ne 256) {
            throw "Capture period mismatch at edge $index`: $measuredPeriod"
        }
    }

    $duty = [math]::Round(100.0 * $high / $period, 3)
    Write-Host "HARDWARE ANALYZER PASS: status='$status' frequency=${frequency}Hz period=$period high=$high duty=$duty% samples=$count rises=$($rises.Count) high_samples=$highSamples"
}
finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}
