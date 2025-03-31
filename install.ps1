<#
.SYNOPSIS
Installs the GitLab Kubernetes solution from the package
#>

param(
    [switch]$OfflineMode,
    [string]$ConfigPath = ".\variables.ps1"
)

# Verify prerequisites
if (-not (Test-Path ".\scripts\bootstrap.ps1")) {
    throw "Package appears corrupted. Missing bootstrap script."
}

# Copy configuration if provided
if ($ConfigPath -ne ".\variables.ps1" -and (Test-Path $ConfigPath)) {
    Copy-Item -Path $ConfigPath -Destination ".\variables.ps1" -Force
}

# Execute installation
try {
    if ($OfflineMode) {
        .\scripts\bootstrap.ps1 -OfflineMode
    } else {
        .\scripts\bootstrap.ps1
    }
}
catch {
    Write-Host "Installation failed: $_" -ForegroundColor Red
    exit 1
}