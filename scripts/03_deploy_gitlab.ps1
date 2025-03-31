<#
.SYNOPSIS
Deploys GitLab using Helm with configuration based on variables.ps1
#>

param(
    [string]$configPath = ".\variables.ps1"
)

# Load configuration
. (Resolve-Path $configPath)

# Initialize logging
$logFile = "$($LOGGING_CONFIG.LogPath)\gitlab_deploy_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -Append

# Generate dynamic values file path
$dynamicValuesPath = "$($STORAGE_CONFIG.LocalPaths.Config)\gitlab-dynamic-values.yaml"

try {
    # Region: Prepare Custom Values File
    Write-Host "`n=== Generating GitLab Configuration ===" -ForegroundColor Cyan

    $resourceProfile = $RESOURCE_PROFILES[$RESOURCE_PROFILES.ActiveProfile]

    $gitlabValues = @"
global:
  hosts:
    domain: $($GITLAB_CONFIG.Domain)
    https: $($GITLAB_CONFIG.SSL.Enabled)
  ingress:
    configureCertmanager: $($GITLAB_CONFIG.SSL.Enabled -and (-not $GITLAB_CONFIG.SSL.SelfSigned))
    annotations:
      kubernetes.io/ingress.class: $($KUBERNETES_CONFIG.IngressController)

certmanager:
  install: $($GITLAB_CONFIG.SSL.Enabled -and (-not $GITLAB_CONFIG.SSL.SelfSigned))

nginx-ingress:
  enabled: false

postgresql:
  image:
    tag: "13.6"
  resources:
    requests:
      cpu: "$($resourceProfile.Postgres.CPU)"
      memory: "$($resourceProfile.Postgres.Memory)"
  persistence:
    enabled: $($STORAGE_CONFIG.PersistentStorage)
    size: "$($resourceProfile.Postgres.Storage)"

redis:
  resources:
    requests:
      cpu: "$($resourceProfile.Redis.CPU)"
      memory: "$($resourceProfile.Redis.Memory)"
  persistence:
    enabled: $($STORAGE_CONFIG.PersistentStorage)

gitlab:
  gitlab-exporter:
    enabled: $($GITLAB_CONFIG.Features.Monitoring)
  webservice:
    replicas: 1
    resources:
      requests:
        cpu: "$($resourceProfile.Web.CPU)"
        memory: "$($resourceProfile.Web.Memory)"
  sidekiq:
    replicas: 1
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
  task-runner:
    enabled: true

registry:
  enabled: $($GITLAB_CONFIG.Features.Registry)
  nodePort: $($NETWORK_CONFIG.HTTPPort)

prometheus:
  install: $($GITLAB_CONFIG.Features.Prometheus)
  alertmanager:
    enabled: false
  pushgateway:
    enabled: false
  server:
    persistentVolume:
      enabled: $($STORAGE_CONFIG.PersistentStorage)

grafana:
  enabled: $($GITLAB_CONFIG.Features.Grafana)
"@

    # Handle SSL configuration
    if ($GITLAB_CONFIG.SSL.Enabled) {
        if ($GITLAB_CONFIG.SSL.SelfSigned) {
            $gitlabValues += @"

# Self-signed cert configuration
global:
  ingress:
    tls:
      secretName: gitlab-tls
"@
        } else {
            $gitlabValues += @"

# Let's Encrypt configuration
global:
  ingress:
    tls:
      enabled: true
      secretName: gitlab-tls
"@
        }
    }

    $gitlabValues | Out-File -FilePath $dynamicValuesPath -Encoding UTF8
    Write-Host "Generated dynamic values file at $dynamicValuesPath"
    # EndRegion

    # Region: Helm Deployment
    Write-Host "`n=== Deploying GitLab Helm Chart ===" -ForegroundColor Cyan

    $helmArgs = @(
        "upgrade", "--install",
        $HELM_CONFIG.ReleaseName,
        $HELM_CONFIG.ChartPath,
        "--namespace", $KUBERNETES_CONFIG.Namespace,
        "--values", $dynamicValuesPath,
        "--timeout", $HELM_CONFIG.Timeout,
        "--atomic",
        "--create-namespace"
    )

    # Add offline specific flags if needed
    if ($OFFLINE_CONFIG.AirGapped) {
        $helmArgs += @("--set", "global.image.pullPolicy=IfNotPresent")
    }

    # Execute Helm deployment
    helm @helmArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Helm deployment failed with exit code $LASTEXITCODE"
    }
    # EndRegion

    # Region: Post-Install Configuration
    Write-Host "`n=== Applying Post-Install Configurations ===" -ForegroundColor Cyan

    # Wait for pods to initialize
    Write-Host "Waiting for GitLab pods to become ready..."
    $timeout = 600 # 10 minutes
    $startTime = Get-Date

    do {
        $pods = kubectl get pods -n $KUBERNETES_CONFIG.Namespace -l release=$HELM_CONFIG.ReleaseName -o json | ConvertFrom-Json
        $readyPods = $pods.items.status.containerStatuses | Where-Object { $_.ready -eq $true }
        $percentReady = [math]::Round(($readyPods.Count / $pods.items.Count) * 100)
        
        Write-Host "Status: $percentReady% ready ($($readyPods.Count)/$($pods.items.Count))"
        
        if ((Get-Date) - $startTime -gt [TimeSpan]::FromSeconds($timeout)) {
            throw "Timed out waiting for pods to become ready"
        }
        
        Start-Sleep -Seconds 10
    } until ($percentReady -eq 100)

    # Apply network policies if enabled
    if ($SECURITY_CONFIG.NetworkPolicy) {
          $networkPolicyYaml = @"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitlab-network-policy
  namespace: $($KUBERNETES_CONFIG.Namespace)
spec:
  podSelector:
    matchLabels:
      release: $($HELM_CONFIG.ReleaseName)
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: $($KUBERNETES_CONFIG.Namespace)
  egress:
  - {}
"@

      # Method 1: Pipe directly to kubectl
      $networkPolicyYaml | kubectl apply -f -

      # Method 2: Use temporary file (more reliable for complex YAML)
      #$tempFile = New-TemporaryFile
      #try {
      #    $networkPolicyYaml | Out-File -FilePath $tempFile.FullName -Encoding utf8
      #    kubectl apply -f $tempFile.FullName
      #}
      #finally {
      #    Remove-Item -Path $tempFile.FullName -ErrorAction SilentlyContinue
      #}
    }
    # EndRegion

    Write-Host "`nGitLab deployment completed successfully!" -ForegroundColor Green
    Write-Host "Access URL: http$('s' * $GITLAB_CONFIG.SSL.Enabled)://$($GITLAB_CONFIG.Domain)" -ForegroundColor Cyan
}
catch {
    Write-Host "`n[ERROR] GitLab deployment failed: $_" -ForegroundColor Red
    exit 3
}
finally {
    Stop-Transcript | Out-Null
}