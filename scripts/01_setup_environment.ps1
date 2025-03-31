<#
.SYNOPSIS
Validates system prerequisites and prepares the deployment environment
#>

param(
    [string]$configPath = ".\variables.ps1",
    [switch]$validateOnly
)

# Load global configuration
. (Resolve-Path $configPath)

# Region: Initialize Logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = "$($LOGGING_CONFIG.LogPath)\env_setup_$timestamp.log"
New-Item -Path $LOGGING_CONFIG.LogPath -ItemType Directory -Force | Out-Null
Start-Transcript -Path $logFile -Append
# EndRegion

try {
    # Region: System Validation
    Write-Host "`n=== Validating System Prerequisites ===" -ForegroundColor Cyan

    # Check Windows version
    $osInfo = [System.Environment]::OSVersion
    if ($osInfo.Version -lt [Version]$VALIDATION.OSVersion) {
        throw "Unsupported OS version. Minimum required: $($VALIDATION.OSVersion)"
    }

    # Check memory
    $memory = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    if ($memory -lt $VALIDATION.MinimumMemoryGB) {
        throw "Insufficient memory. Minimum required: $($VALIDATION.MinimumMemoryGB) GB"
    }

    # Check ports
    $usedPorts = Get-NetTCPConnection | 
        Where-Object { $_.LocalPort -in $VALIDATION.RequiredPorts } |
        Select-Object -ExpandProperty LocalPort -Unique
    if ($usedPorts) {
        throw "Conflicting ports in use: $($usedPorts -join ', ')"
    }

    if ($validateOnly) {
        Write-Host "Validation completed successfully" -ForegroundColor Green
        return
    }
    # EndRegion

    # Region: Dependency Checks
    Write-Host "`n=== Checking Required Dependencies ===" -ForegroundColor Cyan

    $requiredFeatures = @(
        @{Name = "Containers"; Type = "WindowsFeature"},
        @{Name = "Hyper-V"; Type = "WindowsFeature"},
        @{Name = "WSL"; Type = "WindowsFeature"}
    )

    foreach ($feature in $requiredFeatures) {
        $status = if ($feature.Type -eq "WindowsFeature") {
            Get-WindowsOptionalFeature -Online -FeatureName $feature.Name
        }
        
        if ($status.State -ne "Enabled") {
            throw "Required feature not enabled: $($feature.Name)"
        }
    }

    $requiredTools = @(
        @{Name = "Docker"; Command = "docker --version"},
        @{Name = "kubectl"; Command = "kubectl version --client"},
        @{Name = "Helm"; Command = "helm version"}
    )

    foreach ($tool in $requiredTools) {
        try {
            Invoke-Expression $tool.Command | Out-Null
        } catch {
            throw "Missing required tool: $($tool.Name)"
        }
    }
    # EndRegion

    # Region: Prepare Kubernetes Environment
    Write-Host "`n=== Initializing Kubernetes Context ===" -ForegroundColor Cyan

    # Set kubectl context
    kubectl config use-context $KUBERNETES_CONFIG.Context | Out-Null

    # Create namespace if not exists
    $nsExists = kubectl get namespace $KUBERNETES_CONFIG.Namespace -o name 2>$null
    if (-not $nsExists) {
        kubectl create namespace $KUBERNETES_CONFIG.Namespace | Out-Null
    }

    # Configure storage class using PowerShell-native here-string
    if ($STORAGE_CONFIG.PersistentStorage) {
        $storageClassYaml = @"
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $($KUBERNETES_CONFIG.StorageClass)
provisioner: docker.io/hostpath
volumeBindingMode: WaitForFirstConsumer
"@
        $storageClassYaml | kubectl apply -f -
    }
    # EndRegion

    # Region: Prepare Local Directories
    Write-Host "`n=== Creating Local Storage ===" -ForegroundColor Cyan
    $directories = @(
        $STORAGE_CONFIG.LocalPaths.Backup,
        $STORAGE_CONFIG.LocalPaths.Config,
        "$($LOGGING_CONFIG.LogPath)\kube"
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $dir"
        }
    }
    # EndRegion

    Write-Host "`nEnvironment setup completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Environment setup failed: $_" -ForegroundColor Red
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}