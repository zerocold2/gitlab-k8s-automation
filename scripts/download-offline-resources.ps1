<#
.SYNOPSIS
Downloads all required offline resources for GitLab Kubernetes deployment
#>

param(
    [string]$OutputPath = ".\offline-resources",
    [switch]$IncludeContainerImages = $true,
    [switch]$IncludeHelmCharts = $true
)

# Load configuration
$configPath = Join-Path $PSScriptRoot "variables.ps1"
. $configPath

# Create output directories
$directories = @(
    "$OutputPath",
    "$OutputPath\charts",
    "$OutputPath\images"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Initialize log file
$logFile = "$OutputPath\download-resources_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
    # Region: Download Helm Charts
    if ($IncludeHelmCharts) {
        Write-Host "`n=== Downloading Helm Charts ===" -ForegroundColor Cyan

        $charts = @(
            @{Name = "gitlab/gitlab"; Version = $HELM_CONFIG.ChartVersion},
            @{Name = "jetstack/cert-manager"; Version = "v1.11.0"},
            @{Name = "ingress-nginx/ingress-nginx"; Version = "4.7.1"}
        )

        foreach ($chart in $charts) {
            $chartFile = "$OutputPath\charts\$($chart.Name.Split('/')[-1])-$($chart.Version).tgz"
            Write-Host "Downloading $($chart.Name) version $($chart.Version)..."
            helm pull $chart.Name --version $chart.Version --destination "$OutputPath\charts"
            
            if (Test-Path $chartFile) {
                $size = [math]::Round((Get-Item $chartFile).Length / 1MB, 2)
                Write-Host "Downloaded: $chartFile ($size MB)" -ForegroundColor Green
            } else {
                Write-Warning "Failed to download $($chart.Name)"
            }
        }
    }
    # EndRegion

    # Region: Download Container Images
    if ($IncludeContainerImages) {
        Write-Host "`n=== Downloading Container Images ===" -ForegroundColor Cyan

        $images = @(
            "gitlab/gitlab-ce:$($GITLAB_CONFIG.Version)",
            "postgres:13.6",
            "redis:6.2-alpine",
            "prom/prometheus:v2.37.0",
            "grafana/grafana:9.1.2",
            "docker.io/bitnami/kubectl:1.27.3"
        )

        foreach ($image in $images) {
            $imageFile = "$OutputPath\images\$($image.Replace(':','-').Replace('/','-')).tar"
            Write-Host "Downloading $image..."
            
            try {
                docker pull $image
                docker save $image -o $imageFile
                
                if (Test-Path $imageFile) {
                    $size = [math]::Round((Get-Item $imageFile).Length / 1MB, 2)
                    Write-Host "Saved: $imageFile ($size MB)" -ForegroundColor Green
                } else {
                    Write-Warning "Failed to save $image"
                }
            } catch {
                Write-Warning "Error processing $image : $_"
            }
        }
    }
    # EndRegion

    # Region: Download Additional Tools
    Write-Host "`n=== Downloading Utility Binaries ===" -ForegroundColor Cyan

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
        $toolFile = "$OutputPath\$($tool.Name).$($tool.Url.Split('.')[-1])"
        Write-Host "Downloading $($tool.Name)..."
        
        try {
            Invoke-WebRequest -Uri $tool.Url -OutFile $toolFile
            if (Test-Path $toolFile) {
                $size = [math]::Round((Get-Item $toolFile).Length / 1MB, 2)
                Write-Host "Downloaded: $toolFile ($size MB)" -ForegroundColor Green
            }
        } catch {
            Write-Warning "Failed to download $($tool.Name): $_"
        }
    }
    # EndRegion

    Write-Host "`n=== Download Summary ===" -ForegroundColor Green
    Write-Host "Helm Charts: $(@(Get-ChildItem "$OutputPath\charts\*.tgz").Count) downloaded"
    Write-Host "Container Images: $(@(Get-ChildItem "$OutputPath\images\*.tar").Count) saved"
    Write-Host "Utility Binaries: $(@(Get-ChildItem "$OutputPath\*.exe", "$OutputPath\*.zip").Count) downloaded"
    Write-Host "`nAll offline resources have been downloaded to $OutputPath" -ForegroundColor Cyan
}
catch {
    Write-Host "`n[ERROR] Download failed: $_" -ForegroundColor Red
    exit 1
}
finally {
    Stop-Transcript
}