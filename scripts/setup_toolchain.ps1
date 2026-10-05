#Requires -Version 5.1
# The pinned Windows x64 toolchain requires a 64-bit PowerShell process.
# Status goes to the host; the only success-stream output is the command prefix.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($env:OS -ne "Windows_NT" -or -not [Environment]::Is64BitProcess) {
    throw "The pinned xPack toolchain requires 64-bit Windows PowerShell."
}

$Root = Split-Path -Parent $PSScriptRoot
$Spec = Get-Content -LiteralPath (Join-Path $Root "tools\toolchain.json") -Raw | ConvertFrom-Json
if ($Spec.version -notmatch '^\d+\.\d+\.\d+-\d+$' -or
    $Spec.platform -ne "win32-x64" -or $Spec.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw "Invalid pinned toolchain metadata in tools\toolchain.json."
}

$LocalRoot = [IO.Path]::GetFullPath((Join-Path $Root "tools\.local"))
$DirectoryName = "xpack-riscv-none-elf-gcc-$($Spec.version)"
$InstallDirectory = Join-Path $LocalRoot $DirectoryName
$DownloadDirectory = Join-Path $LocalRoot "downloads"
$Archive = Join-Path $DownloadDirectory "$DirectoryName-$($Spec.platform).zip"
$CompilerVersion = ($Spec.version -split '-')[0]
$Prefix = Join-Path $InstallDirectory "bin\riscv-none-elf"

function Test-Toolchain {
    param([string]$Directory, [switch]$RequireReceipt)

    foreach ($suffix in @("gcc", "objcopy", "objdump", "size")) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory "bin\riscv-none-elf-$suffix.exe") -PathType Leaf)) {
            return $false
        }
    }
    if ($RequireReceipt) {
        $receipt = Join-Path $Directory ".archive-sha256"
        if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { return $false }
        if ((Get-Content -LiteralPath $receipt -Raw).Trim() -ne $Spec.sha256) { return $false }
    }
    try {
        $version = & (Join-Path $Directory "bin\riscv-none-elf-gcc.exe") -dumpfullversion 2>$null
        return ($LASTEXITCODE -eq 0 -and ($version -join "").Trim() -eq $CompilerVersion)
    } catch {
        return $false
    }
}

function Remove-LocalDirectory {
    param([string]$Path)

    # Check the absolute target before deleting a generated cache directory.
    $absolute = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetDirectoryName($absolute) -ne $LocalRoot) {
        throw "Refusing to remove a directory outside tools\.local: $absolute"
    }
    if (Test-Path -LiteralPath $absolute) {
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
}

if (Test-Toolchain $InstallDirectory -RequireReceipt) {
    Write-Host "TOOLCHAIN READY: xPack RISC-V GCC $($Spec.version) (local cache)"
    return $Prefix
}

New-Item -ItemType Directory -Force -Path $LocalRoot, $DownloadDirectory | Out-Null
$Lock = $null
$PartialArchive = $null
$StagingDirectory = $null
try {
    # An exclusive handle prevents two installers from changing the same cache.
    try {
        $Lock = [IO.File]::Open((Join-Path $LocalRoot ".setup.lock"),
            [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot lock tools\.local for setup. Check permissions or wait for the other setup to finish, then rerun. $($_.Exception.Message)"
    }

    if (-not (Test-Toolchain $InstallDirectory -RequireReceipt)) {
        if (Test-Path -LiteralPath $Archive -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $Spec.sha256) {
                Write-Host "Cached toolchain ZIP failed SHA-256 verification; downloading a fresh copy."
                Remove-Item -LiteralPath $Archive -Force
            }
        }
        if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
            Write-Host "Downloading xPack RISC-V GCC $($Spec.version) from GitHub (about 444 MiB)..."
            $PartialArchive = "$Archive.$([guid]::NewGuid().ToString('N')).part"
            $PreviousProgress = $ProgressPreference
            $PreviousTls = [Net.ServicePointManager]::SecurityProtocol
            try {
                $ProgressPreference = "SilentlyContinue"
                [Net.ServicePointManager]::SecurityProtocol = $PreviousTls -bor [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $Spec.url -OutFile $PartialArchive -UseBasicParsing -TimeoutSec 600
                if ((Get-FileHash -LiteralPath $PartialArchive -Algorithm SHA256).Hash -ne $Spec.sha256) {
                    throw "The downloaded ZIP does not match the pinned SHA-256."
                }
                Move-Item -LiteralPath $PartialArchive -Destination $Archive
                $PartialArchive = $null
            } catch {
                throw "Toolchain download failed. Check network/proxy access to GitHub and rerun scripts\build_freertos.ps1. $($_.Exception.Message)"
            } finally {
                $ProgressPreference = $PreviousProgress
                [Net.ServicePointManager]::SecurityProtocol = $PreviousTls
            }
        }

        Write-Host "Extracting the verified toolchain ZIP into tools\.local..."
        $StagingDirectory = Join-Path $LocalRoot ".extract-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $StagingDirectory | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $StagingDirectory)
        $ExtractedDirectory = Join-Path $StagingDirectory $DirectoryName
        if (-not (Test-Toolchain $ExtractedDirectory)) {
            throw "The extracted xPack toolchain is incomplete or cannot run on this computer."
        }
        Set-Content -LiteralPath (Join-Path $ExtractedDirectory ".archive-sha256") -Value $Spec.sha256 -Encoding ascii

        # Only replace an incomplete installation after its replacement passes validation.
        Remove-LocalDirectory $InstallDirectory
        $absoluteSource = [IO.Path]::GetFullPath($ExtractedDirectory)
        $absoluteTarget = [IO.Path]::GetFullPath($InstallDirectory)
        if ([IO.Path]::GetDirectoryName($absoluteSource) -ne $StagingDirectory -or
            [IO.Path]::GetDirectoryName($absoluteTarget) -ne $LocalRoot) {
            throw "Refusing to move the toolchain outside its staging and installation directories."
        }
        Move-Item -LiteralPath $absoluteSource -Destination $absoluteTarget
    }
} finally {
    try {
        if ($PartialArchive -and (Test-Path -LiteralPath $PartialArchive)) {
            Remove-Item -LiteralPath $PartialArchive -Force
        }
        if ($StagingDirectory) { Remove-LocalDirectory $StagingDirectory }
    } finally {
        if ($Lock) { $Lock.Dispose() }
    }
}

Write-Host "TOOLCHAIN READY: xPack RISC-V GCC $($Spec.version)"
return $Prefix
