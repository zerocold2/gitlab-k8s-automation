<#
.SYNOPSIS
Initializes Kubernetes cluster and installs required components for GitLab
#>

param(
    [string]$configPath = ".\variables.ps1"
)

# Load configuration
. (Resolve-Path $configPath)

# Initialize logging
$logFile = "$($LOGGING_CONFIG.LogPath)\kube_install_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
    # Region: Verify Docker Desktop Kubernetes
    Write-Host "`n=== Activating Kubernetes in Docker Desktop ===" -ForegroundColor Cyan

    $dockerConfig = Get-Content "$env:APPDATA\Docker\settings.json" | ConvertFrom-Json
    if (-not $dockerConfig.kubernetes.enabled) {
        Write-Host "Enabling Kubernetes cluster..." -ForegroundColor Yellow
        & "C:\Program Files\Docker\Docker\Docker Desktop.exe" --install-kubernetes
        
        # Wait for cluster to be ready
        $timeout = 300 # 5 minutes
        $interval = 10
        $elapsed = 0
        do {
            Start-Sleep -Seconds $interval
            $elapsed += $interval
            $status = kubectl cluster-info 2>&1
        } until ($status -like "*is running*" -or $elapsed -ge $timeout)

        if ($elapsed -ge $timeout) {
            throw "Kubernetes cluster failed to start within timeout period"
        }
    }
    # EndRegion

    # Region: Install Ingress Controller
    if ($KUBERNETES_CONFIG.EnableIngress) {
        Write-Host "`n=== Deploying $($KUBERNETES_CONFIG.IngressController) Ingress ===" -ForegroundColor Cyan

        switch ($KUBERNETES_CONFIG.IngressController) {
            "nginx" {
                if ($OFFLINE_CONFIG.AirGapped) {
                    helm install ingress-nginx ".\offline-resources\nginx-ingress.tgz" `
                        --namespace $KUBERNETES_CONFIG.Namespace `
                        --set controller.service.type=$NETWORK_CONFIG.ServiceType `
                        --set controller.service.nodePorts.http=$NETWORK_CONFIG.HTTPPort `
                        --set controller.service.nodePorts.https=$NETWORK_CONFIG.HTTPSPort
                }
                else {
                    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
                    helm install ingress-nginx ingress-nginx/ingress-nginx `
                        --namespace $KUBERNETES_CONFIG.Namespace `
                        --set controller.service.type=$NETWORK_CONFIG.ServiceType `
                        --set controller.service.nodePorts.http=$NETWORK_CONFIG.HTTPPort `
                        --set controller.service.nodePorts.https=$NETWORK_CONFIG.HTTPSPort
                }
            }
            
            "traefik" {
                # Similar implementation for Traefik
                # ...
            }
        }

        # Verify ingress installation
        $ingressReady = $false
        $retries = 0
        do {
            $ingressStatus = kubectl get pods -n $KUBERNETES_CONFIG.Namespace -l app.kubernetes.io/name=ingress-nginx -o json | ConvertFrom-Json
            if ($ingressStatus.items.status.containerStatuses[0].ready) {
                $ingressReady = $true
            }
            else {
                Start-Sleep -Seconds 10
                $retries++
            }
        } until ($ingressReady -or $retries -ge 12) # 2 minute timeout
    }
    # EndRegion

    # Region: Install Cert-Manager (for SSL)
    if ($GITLAB_CONFIG.SSL.Enabled -and -not $GITLAB_CONFIG.SSL.SelfSigned) {
        Write-Host "`n=== Installing Cert-Manager ===" -ForegroundColor Cyan

        if ($OFFLINE_CONFIG.AirGapped) {
            helm install cert-manager ".\offline-resources\cert-manager.tgz" `
                --namespace $KUBERNETES_CONFIG.Namespace `
                --version v1.11.0 `
                --set installCRDs=true
        }
        else {
            helm repo add jetstack https://charts.jetstack.io
            helm install cert-manager jetstack/cert-manager `
                --namespace $KUBERNETES_CONFIG.Namespace `
                --version v1.11.0 `
                --set installCRDs=true
        }

        # Apply ClusterIssuer for Let's Encrypt
        if (-not $OFFLINE_CONFIG.AirGapped) {
            $yamlString = "@
            apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@$($GITLAB_CONFIG.Domain)
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
@"            
            $yamlString | kubectl apply -f - 
        }
    }
    # EndRegion

    # Region: Load Container Images (Offline Mode)
    if ($OFFLINE_CONFIG.AirGapped) {
        Write-Host "`n=== Loading Pre-Downloaded Images ===" -ForegroundColor Cyan
        $imageDir = ".\offline-resources\images"
        
        if (Test-Path $imageDir) {
            Get-ChildItem "$imageDir\*.tar" | ForEach-Object {
                Write-Host "Loading $($_.Name)..."
                docker load -i $_.FullName
            }
        }
        else {
            Write-Warning "Offline image directory not found at $imageDir"
        }
    }
    # EndRegion

    Write-Host "`nKubernetes initialization completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Kubernetes setup failed: $_" -ForegroundColor Red
    exit 2
}
finally {
    Stop-Transcript | Out-Null
}