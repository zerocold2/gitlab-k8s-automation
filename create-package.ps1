<#
.SYNOPSIS
Creates a distributable package of the GitLab Kubernetes solution
#>

param(
    [string]$OutputPath = ".\gitlab-k8s-package",
    [switch]$IncludeBinaries,
    [switch]$CreateZip
)

# Create directory structure
$dirs = @(
    "$OutputPath",
    "$OutputPath\bin",
    "$OutputPath\configs",
    "$OutputPath\docs",
    "$OutputPath\examples",
    "$OutputPath\manifests",
    "$OutputPath\scripts",
    "$OutputPath\tools"
)

$dirs | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# Copy core files
$filesToCopy = @(
    @{Source = ".\scripts\*.ps1"; Dest = "$OutputPath\scripts"},
    @{Source = ".\configs\*.yaml"; Dest = "$OutputPath\configs"},
    @{Source = ".\README.md"; Dest = $OutputPath},
    @{Source = ".\LICENSE"; Dest = $OutputPath},
    @{Source = ".\variables.ps1"; Dest = $OutputPath}
)

foreach ($file in $filesToCopy) {
    Copy-Item -Path $file.Source -Destination $file.Dest -Force
}

# Create documentation
@"
# GitLab Kubernetes Installation Guide

## Online Installation
1. Run `.\scripts\bootstrap.ps1`
2. Follow the prompts

## Offline Installation
See OFFLINE_SETUP.md
"@ | Out-File -FilePath "$OutputPath\docs\INSTALL.md" -Encoding utf8

@"
# Offline Installation Guide

1. Place offline resources in `.\offline-resources\`
2. Run `.\scripts\bootstrap.ps1 -OfflineMode`
"@ | Out-File -FilePath "$OutputPath\docs\OFFLINE_SETUP.md" -Encoding utf8

# Include binaries if requested
if ($IncludeBinaries) {
    Write-Host "Downloading required binaries..." -ForegroundColor Cyan
    $tools = @(
        @{
            Name = "kubectl";
            Url = "https://dl.k8s.io/release/v1.27.3/bin/windows/amd64/kubectl.exe"
        },
        @{
            Name = "helm";
            Url = "https://get.helm.sh/helm-v3.12.2-windows-amd64.zip"
        }
    )

    foreach ($tool in $tools) {
        try {
            Invoke-WebRequest -Uri $tool.Url -OutFile "$OutputPath\tools\$($tool.Name).$($tool.Url.Split('.')[-1])"
        } catch {
            Write-Warning "Failed to download $($tool.Name): $_"
        }
    }
}

# Create ZIP archive if requested
if ($CreateZip) {
    $zipPath = "$OutputPath.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    Compress-Archive -Path "$OutputPath\*" -DestinationPath $zipPath
    Write-Host "Package created at $zipPath" -ForegroundColor Green
}

Write-Host "Packaging complete! Contents available at $OutputPath" -ForegroundColor Green