param(
    [string]$ToolchainPrefix,
    [string]$VivadoBin
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

& "$PSScriptRoot\build_freertos.ps1" -ToolchainPrefix $ToolchainPrefix
if ($LASTEXITCODE -ne 0) { throw "FreeRTOS build failed" }
& "$PSScriptRoot\test.ps1" -VivadoBin $VivadoBin
if ($LASTEXITCODE -ne 0) { throw "FreeRTOS simulation failed" }
