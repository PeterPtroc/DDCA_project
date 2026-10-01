param(
    [string]$Port = "COM9",
    [Parameter(Mandatory = $true)]
    [int]$ExpectedPeriod,
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 99)]
    [int]$ExpectedDutyPercent,
    [string]$Label = "",
    [ValidateRange(1, 100)]
    [int]$Samples = 10,
    [ValidateRange(0, 10)]
    [int]$TickTolerance = 1,
    [string]$OutputCsv = "build\hardware\characterization.csv"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Read-Exact {
    param([System.IO.Ports.SerialPort]$Serial, [int]$Count)
    $buffer = [byte[]]::new($Count)
    $received = 0
    while ($received -lt $Count) {
        $received += $Serial.Read($buffer, $received, $Count - $received)
    }
    return $buffer
}

$expectedHigh = [int][math]::Floor(
    ([int64]$ExpectedPeriod * $ExpectedDutyPercent) / 100.0
)
$expectedLow = $ExpectedPeriod - $expectedHigh
$expectedFrequency = [int][math]::Floor(100000000.0 / $ExpectedPeriod)
if ([string]::IsNullOrWhiteSpace($Label)) {
    $Label = "${expectedFrequency}Hz_${ExpectedDutyPercent}pct"
}

$serial = [System.IO.Ports.SerialPort]::new(
    $Port, 115200, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One
)
$serial.ReadTimeout = 5000
$serial.WriteTimeout = 3000
$rows = [System.Collections.Generic.List[object]]::new()

try {
    $serial.Open()
    Start-Sleep -Milliseconds 1200
    $serial.DiscardInBuffer()

    for ($index = 0; $index -lt $Samples; $index++) {
        $serial.Write("m")
        $packet = Read-Exact $serial 24
        $magic = [Text.Encoding]::ASCII.GetString($packet, 0, 4)
        $flags = [BitConverter]::ToUInt32($packet, 4)
        if ($magic -ne "MEA2" -or ($flags -band 3) -ne 3) {
            throw "Invalid MEA2 sample $($index + 1): magic=$magic flags=$flags"
        }
        $rows.Add([pscustomobject]@{
            Frequency = [BitConverter]::ToUInt32($packet, 8)
            Period    = [BitConverter]::ToUInt32($packet, 12)
            High      = [BitConverter]::ToUInt32($packet, 16)
            Low       = [BitConverter]::ToUInt32($packet, 20)
        })
        Start-Sleep -Milliseconds 50
    }
}
finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}

$frequencyMin = ($rows.Frequency | Measure-Object -Minimum).Minimum
$frequencyMax = ($rows.Frequency | Measure-Object -Maximum).Maximum
$periodMin = ($rows.Period | Measure-Object -Minimum).Minimum
$periodMax = ($rows.Period | Measure-Object -Maximum).Maximum
$highMin = ($rows.High | Measure-Object -Minimum).Minimum
$highMax = ($rows.High | Measure-Object -Maximum).Maximum
$lowMin = ($rows.Low | Measure-Object -Minimum).Minimum
$lowMax = ($rows.Low | Measure-Object -Maximum).Maximum
$periodError = [math]::Max(
    [math]::Abs([int64]$periodMin - $ExpectedPeriod),
    [math]::Abs([int64]$periodMax - $ExpectedPeriod)
)
$highError = [math]::Max(
    [math]::Abs([int64]$highMin - $expectedHigh),
    [math]::Abs([int64]$highMax - $expectedHigh)
)
$lowError = [math]::Max(
    [math]::Abs([int64]$lowMin - $expectedLow),
    [math]::Abs([int64]$lowMax - $expectedLow)
)
$passed = $periodError -le $TickTolerance -and
    $highError -le $TickTolerance -and $lowError -le $TickTolerance

$root = Split-Path -Parent $PSScriptRoot
$bitstreamPath = Join-Path $root "build\vivado\rv32_realtime_scope.bit"
if (-not (Test-Path -LiteralPath $bitstreamPath)) {
    throw "Bitstream not found for characterization provenance: $bitstreamPath"
}
$bitstreamSha256 = (Get-FileHash -LiteralPath $bitstreamPath -Algorithm SHA256).Hash
$csvPath = if ([IO.Path]::IsPathRooted($OutputCsv)) {
    $OutputCsv
}
else {
    Join-Path $root $OutputCsv
}
$csvDirectory = Split-Path -Parent $csvPath
New-Item -ItemType Directory -Path $csvDirectory -Force | Out-Null
$result = [pscustomobject][ordered]@{
    Timestamp            = (Get-Date).ToString("o")
    BitstreamSha256       = $bitstreamSha256
    Port                 = $Port
    Label                = $Label
    Samples              = $Samples
    ExpectedFrequencyHz  = $expectedFrequency
    ExpectedPeriodTicks  = $ExpectedPeriod
    ExpectedHighTicks    = $expectedHigh
    ExpectedLowTicks     = $expectedLow
    DutyPercent          = $ExpectedDutyPercent
    FrequencyMinHz       = $frequencyMin
    FrequencyMaxHz       = $frequencyMax
    PeriodMinTicks       = $periodMin
    PeriodMaxTicks       = $periodMax
    HighMinTicks         = $highMin
    HighMaxTicks         = $highMax
    LowMinTicks          = $lowMin
    LowMaxTicks          = $lowMax
    MaxPeriodErrorTicks  = $periodError
    MaxHighErrorTicks    = $highError
    MaxLowErrorTicks     = $lowError
    Result               = if ($passed) { "PASS" } else { "FAIL" }
}
$result | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append

if (-not $passed) {
    throw "CHARACTERIZATION FAIL '$Label': period=$periodMin..$periodMax high=$highMin..$highMax low=$lowMin..$lowMax expected=$ExpectedPeriod/$expectedHigh/$expectedLow tolerance=$TickTolerance"
}

Write-Host "CHARACTERIZATION PASS '$Label': frequency=${frequencyMin}..${frequencyMax}Hz period=$periodMin..$periodMax high=$highMin..$highMax low=$lowMin..$lowMax samples=$Samples csv='$csvPath'"
