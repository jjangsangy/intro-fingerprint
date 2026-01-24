# install.ps1 - Installer for intro-fingerprint on Windows

$ErrorActionPreference = "Stop"

# Configuration
$DownloadUrl = "https://github.com/jjangsangy/intro-fingerprint/releases/latest/download/intro-fingerprint.zip"
$TempFile = Join-Path $env:TEMP "intro-fingerprint-install.zip"
$TargetPath = "scripts\intro-fingerprint"
$BackupName = ".intro-fingerprint-backup"

# Helper functions
function Write-Info { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message) Write-Error $Message }

# 1. Determine MPV configuration directory
if ($env:MPV_HOME) {
    $ConfigDir = $env:MPV_HOME
} elseif ($env:MPV_CONFIG_DIR) {
    $ConfigDir = $env:MPV_CONFIG_DIR
} else {
    $ConfigDir = Join-Path $env:APPDATA "mpv"
}

$InstallDir = Join-Path $ConfigDir $TargetPath
$BackupDir = Join-Path $ConfigDir $BackupName

Write-Info "Target directory: $ConfigDir"

# Ensure config directory exists
if (-not (Test-Path -Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir | Out-Null
}

# Clean up any previous backup
if (Test-Path -Path $BackupDir) {
    Remove-Item -Path $BackupDir -Recurse -Force
}

# Backup existing installation
if (Test-Path -Path $InstallDir) {
    Write-Info "Backing up existing installation..."
    $BackupTarget = Join-Path $BackupDir $TargetPath
    $BackupParent = Split-Path $BackupTarget -Parent
    if (-not (Test-Path $BackupParent)) {
        New-Item -ItemType Directory -Path $BackupParent -Force | Out-Null
    }
    Move-Item -Path $InstallDir -Destination $BackupTarget
}

# Download
Write-Info "Downloading..."
try {
    # Using SecurityProtocol Tls12 is sometimes needed on older PowerShell/Windows versions
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempFile -UseBasicParsing
} catch {
    Write-Error "Download failed: $_"
    # Attempt restore
    if (Test-Path -Path $BackupDir) {
        Write-Info "Download failed. Restoring backup..."
        Move-Item -Path $BackupTarget -Destination $InstallDir
    }
    exit 1
}

# Extract
Write-Info "Installing..."
try {
    # Expand-Archive extracts to destination. If zip contains 'scripts/intro-fingerprint', we extract to $ConfigDir.
    Expand-Archive -Path $TempFile -DestinationPath $ConfigDir -Force
} catch {
    Write-Error "Extraction failed: $_"
    exit 1
}

# Cleanup
if (Test-Path -Path $TempFile) { Remove-Item -Path $TempFile }
if (Test-Path -Path $BackupDir) { Remove-Item -Path $BackupDir -Recurse -Force }

Write-Success "intro-fingerprint successfully installed."
