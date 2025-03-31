<#
.SYNOPSIS
Performs post-installation configuration of GitLab including security, integrations, and backups
#>

param(
    [string]$configPath = ".\variables.ps1"
)

# Load configuration
. (Resolve-Path $configPath)

# Initialize logging
$logFile = "$($LOGGING_CONFIG.LogPath)\gitlab_config_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -Path $LOGGING_CONFIG.LogPath -ItemType Directory -Force | Out-Null
Start-Transcript -Path $logFile -Append

try {
    # Region: Wait for GitLab Readiness
    Write-Host "`n=== Verifying GitLab Availability ===" -ForegroundColor Cyan
    
    $gitlabPod = kubectl get pods -n $KUBERNETES_CONFIG.Namespace -l app=webservice -o jsonpath='{.items[0].metadata.name}'
    $timeout = 900 # 15 minutes
    $startTime = Get-Date
    
    do {
        $status = kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -- curl -s http://localhost/-/health
        if ($status -eq "GitLab OK") {
            break
        }
        
        if ((Get-Date) - $startTime -gt [TimeSpan]::FromSeconds($timeout)) {
            throw "Timed out waiting for GitLab to become ready"
        }
        $timeElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
        Write-Host "Waiting for GitLab to respond... (Elapsed: $timeElapsed s)"
        Start-Sleep -Seconds 30
    } while ($true)
    # EndRegion

    # Region: Configure Root Password
    Write-Host "`n=== Configuring Root Password ===" -ForegroundColor Cyan
    
    $ENCRYPTED_PASSWORD = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($GITLAB_CONFIG.InitialRootPassword))
    
    kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -- gitlab-rails runner "user = User.find_by_username('root'); user.password = '$($GITLAB_CONFIG.InitialRootPassword)'; user.password_confirmation = '$($GITLAB_CONFIG.InitialRootPassword)'; user.save!"
    
    # Verify password change
    $authTest = kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -- curl -X POST -H "Content-Type: application/json" -d "{\`"username\`":\`"root\`",\`"password\`":\`"$($GITLAB_CONFIG.InitialRootPassword)\`"}" http://localhost/api/v4/session 2>$null | ConvertFrom-Json
    if (-not $authTest.private_token) {
        throw "Failed to verify root password configuration"
    }
    # EndRegion

    # Region: Configure SMTP
    if ($EXTERNAL_SERVICES.SMTP.Enabled) {
        Write-Host "`n=== Configuring SMTP ===" -ForegroundColor Cyan
        
        $smtpConfig = @"
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "$($EXTERNAL_SERVICES.SMTP.Host)"
gitlab_rails['smtp_port'] = $($EXTERNAL_SERVICES.SMTP.Port)
gitlab_rails['smtp_user_name'] = "$($EXTERNAL_SERVICES.SMTP.User)"
gitlab_rails['smtp_password'] = "$($EXTERNAL_SERVICES.SMTP.Password)"
gitlab_rails['smtp_domain'] = "$($GITLAB_CONFIG.Domain)"
gitlab_rails['smtp_authentication'] = "login"
gitlab_rails['smtp_enable_starttls_auto'] = true
gitlab_rails['gitlab_email_from'] = "gitlab@$($GITLAB_CONFIG.Domain)"
"@

        $smtpConfig | kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -i -- sh -c "cat > /etc/gitlab/conf.d/smtp.rb"
        kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -- gitlab-ctl reconfigure
        
        # Test email
        kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -- gitlab-rails runner "Notify.test_email('test@example.com', 'SMTP Test', 'SMTP Configuration Successful').deliver_now"
    }
    # EndRegion

    # Region: Configure LDAP
    if ($EXTERNAL_SERVICES.LDAP.Enabled) {
        Write-Host "`n=== Configuring LDAP ===" -ForegroundColor Cyan
        
        $ldapConfig = @"
gitlab_rails['ldap_enabled'] = true
gitlab_rails['ldap_servers'] = {
  'main' => {
    'label' => 'LDAP',
    'host' => '$($EXTERNAL_SERVICES.LDAP.Host)',
    'port' => 389,
    'uid' => 'sAMAccountName',
    'bind_dn' => 'CN=Administrator,CN=Users,$($EXTERNAL_SERVICES.LDAP.BaseDN)',
    'password' => '$($EXTERNAL_SERVICES.LDAP.Password)',
    'encryption' => 'plain',
    'verify_certificates' => false,
    'active_directory' => true,
    'base' => '$($EXTERNAL_SERVICES.LDAP.BaseDN)',
    'group_base' => 'OU=Groups,$($EXTERNAL_SERVICES.LDAP.BaseDN)',
    'admin_group' => 'GitLab Admins'
  }
}
"@

        $ldapConfig | kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -i -- sh -c "cat > /etc/gitlab/conf.d/ldap.rb"
        kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -- gitlab-ctl reconfigure
    }
    # EndRegion

    # Region: Setup Backup CronJob
    Write-Host "`n=== Configuring Backups ===" -ForegroundColor Cyan
    
    $backupYaml = @"
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: gitlab-backup
  namespace: $($KUBERNETES_CONFIG.Namespace)
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: $($OFFLINE_CONFIG.LocalRegistry)/gitlab/gitlab-ce:latest
            command: ["/bin/bash", "-c"]
            args:
            - gitlab-backup create CRON=1
            - mkdir -p /backups
            - Copy-Item /var/opt/gitlab/backups/* /backups/
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: gitlab-backup-pvc
"@
    $backupYaml | kubectl apply -f -

    # Create backup PVC if not exists
    if (-not (kubectl get pvc -n $KUBERNETES_CONFIG.Namespace gitlab-backup-pvc -o name 2>$null)) {
        $pvcYaml = @"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-backup-pvc
  namespace: $($KUBERNETES_CONFIG.Namespace)
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $($RESOURCE_PROFILES[$RESOURCE_PROFILES.ActiveProfile].Postgres.Storage)
  storageClassName: $($KUBERNETES_CONFIG.StorageClass)
"@
        $pvcYaml | kubectl apply -f -
    }
    # EndRegion

    # Region: Register CI Runners
    Write-Host "`n=== Registering CI Runners ===" -ForegroundColor Cyan
    
    $runnerToken = kubectl exec -n $KUBERNETES_CONFIG.Namespace $gitlabPod -- gitlab-rails runner -e production "puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token"
    
    if ($runnerToken) {
        $runnerYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-runner
  namespace: $($KUBERNETES_CONFIG.Namespace)
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gitlab-runner
  template:
    metadata:
      labels:
        app: gitlab-runner
    spec:
      containers:
      - name: gitlab-runner
        image: gitlab/gitlab-runner:alpine
        env:
        - name: CI_SERVER_URL
          value: "https://$($GITLAB_CONFIG.Domain)"
        - name: REGISTRATION_TOKEN
          value: "$runnerToken"
        - name: RUNNER_EXECUTOR
          value: "docker"
        - name: DOCKER_IMAGE
          value: "docker:stable"
        volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
        - name: config
          mountPath: /etc/gitlab-runner
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
      - name: config
        emptyDir: {}
"@
        $runnerYaml | kubectl apply -f -
    }
    # EndRegion

    # Region: Output Access Information
    Write-Host "`n=== GitLab Configuration Complete ===" -ForegroundColor Green
    Write-Host "Access Information:" -ForegroundColor Cyan
    Write-Host "URL: https://$($GITLAB_CONFIG.Domain)"
    Write-Host "Username: root"
    Write-Host "Password: $($GITLAB_CONFIG.InitialRootPassword)"
    
    if ($EXTERNAL_SERVICES.SMTP.Enabled) {
        Write-Host "SMTP Configured: Yes (Server: $($EXTERNAL_SERVICES.SMTP.Host))"
    }
    
    if ($EXTERNAL_SERVICES.LDAP.Enabled) {
        Write-Host "LDAP Configured: Yes (Server: $($EXTERNAL_SERVICES.LDAP.Host))"
    }
    
    Write-Host "Backups: Enabled (Daily at 2AM)"
    Write-Host "CI Runners: 2 instances registered"
    # EndRegion
}
catch {
    Write-Host "`n[ERROR] GitLab configuration failed: $_" -ForegroundColor Red
    exit 4
}
finally {
    Stop-Transcript | Out-Null
}