param(
    [string]$Port = "COM9",
    [ValidateSet("JA1", "JA2", "JA3", "JA4", "JA7", "JA8", "JA9", "JA10")]
    [string]$ExpectedOutput = "JA9",
    [ValidateRange(1, 1440)]
    [int]$DurationMinutes = 10,
    [ValidateRange(1, 300)]
    [int]$IntervalSeconds = 10,
    [string]$ArtifactDirectory = "build\hardware"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $root $ArtifactDirectory
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $artifactRoot `
    "soak_$($ExpectedOutput.ToLowerInvariant())_$runStamp.log"
$deadline = [DateTime]::UtcNow.AddMinutes($DurationMinutes)
$iteration = 0
$previousCycle = $null
$previousInstret = $null

"Hardware soak started $(Get-Date -Format o), port=$Port, signal=$ExpectedOutput" |
    Set-Content -LiteralPath $logPath

while ([DateTime]::UtcNow -lt $deadline) {
    $iteration++
    $output = & "$PSScriptRoot\test_hardware.ps1" -Port $Port `
        -ExpectedOutput $ExpectedOutput *>&1
    $line = ($output | Select-Object -Last 1).ToString()
    if ($line -notmatch 'cycle=(\d+) instret=(\d+)') {
        throw "Hardware test iteration $iteration returned no performance counters: $line"
    }

    [uint64]$cycle = $Matches[1]
    [uint64]$instret = $Matches[2]
    if ($null -ne $previousCycle) {
        $cycleDelta = ($cycle + 0x100000000L - $previousCycle) % 0x100000000L
        $instretDelta = ($instret + 0x100000000L - $previousInstret) % 0x100000000L
        if ($cycleDelta -eq 0 -or $instretDelta -eq 0) {
            throw "CPU stopped making progress at iteration $iteration"
        }
    }
    $previousCycle = $cycle
    $previousInstret = $instret

    $entry = "$(Get-Date -Format o) iteration=$iteration $line"
    $entry | Tee-Object -FilePath $logPath -Append | Write-Host
    $remainingMilliseconds = [math]::Ceiling(
        ($deadline - [DateTime]::UtcNow).TotalMilliseconds
    )
    if ($remainingMilliseconds -gt 0) {
        $sleepMilliseconds = [math]::Min(
            $IntervalSeconds * 1000, $remainingMilliseconds
        )
        Start-Sleep -Milliseconds $sleepMilliseconds
    }
}

$summary = "HARDWARE SOAK PASS: duration=${DurationMinutes}min iterations=$iteration log=$logPath"
$summary | Tee-Object -FilePath $logPath -Append | Write-Host
