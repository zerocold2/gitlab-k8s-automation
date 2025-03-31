<#
.SYNOPSIS
Orchestrates the GitLab deployment process
#>

param(
    [ValidateSet("minimal", "production")]
    [string]$Profile = "minimal",
    
    [switch]$SkipValidation
)

# Load configuration
. .\variables.ps1
$RESOURCE_PROFILES.ActiveProfile = $Profile

$scriptOrder = @(
    "01_setup_environment.ps1",
    "02_install_kubernetes.ps1",
    "03_deploy_gitlab.ps1",
    "04_configure_gitlab.ps1"
)

foreach ($script in $scriptOrder) {
    try {
        if (-not $SkipValidation -and $script -eq "01_setup_environment.ps1") {
            .\scripts\$script -configPath .\variables.ps1 -validate
        } else {
            .\scripts\$script -configPath .\variables.ps1
        }
        
        Write-Host "✅ $($script.Replace('.ps1','')) completed" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed during $script : $_" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "`n🚀 GitLab deployment completed!" -ForegroundColor Cyan
Write-Host "Access URL: https://$($GITLAB_CONFIG.Domain)" -ForegroundColor Yellow