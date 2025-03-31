<#
.SYNOPSIS
Central configuration file for GitLab on Kubernetes deployment
#>

# Region: Kubernetes Cluster Configuration
$KUBERNETES_CONFIG = @{
    ClusterName       = "gitlab-cluster"
    Context           = "docker-desktop"
    Namespace         = "gitlab-system"
    StorageClass      = "hostpath"  # For Docker Desktop storage
    EnableIngress     = $true
    IngressController = "nginx"     # Options: nginx, traefik, none
}
# EndRegion

# Region: Helm Chart Configuration
$HELM_CONFIG = @{
    ChartVersion      = "7.1.0"     # GitLab Helm chart version
    ChartPath         = ".\offline-resources\gitlab-helm.tgz"
    RepositoryUrl     = "https://charts.gitlab.io/"
    ReleaseName       = "gitlab-ee"
    ValuesFile        = ".\config\gitlab-values.yaml"
    Timeout           = "1200s"     # 20 minutes for installation
}
# EndRegion

# Region: GitLab Core Configuration
$GITLAB_CONFIG = @{
    Domain            = "gitlab.company.local"
    InitialRootPassword = "ChangeMe123!"  # Will be encrypted during setup
    SSL = @{
        Enabled       = $true
        SelfSigned    = $true       # For offline environments
        CertPath      = ".\ssl\gitlab.crt"
        KeyPath       = ".\ssl\gitlab.key"
    }
    Features = @{
        Registry      = $true
        Pages         = $false      # Disable in minimal install
        Monitoring    = $true
        Prometheus    = $true
        Grafana       = $true
    }
}
# EndRegion

# Region: Resource Allocation
$RESOURCE_PROFILES = @{
    # Choose profile: "minimal", "medium", "production"
    ActiveProfile     = "minimal"
    
    Minimal = @{
        Web = @{
            CPU       = "500m"
            Memory    = "2Gi"
        }
        Postgres = @{
            CPU       = "500m"
            Memory    = "2Gi"
            Storage   = "10Gi"
        }
        Redis = @{
            CPU       = "250m"
            Memory    = "1Gi"
        }
    }
    
    Production = @{
        Web = @{
            CPU       = "2"
            Memory    = "4Gi"
        }
        Postgres = @{
            CPU       = "2"
            Memory    = "8Gi"
            Storage   = "100Gi"
        }
        Redis = @{
            CPU       = "1"
            Memory    = "4Gi"
        }
    }
}
# EndRegion

# Region: Network Configuration
$NETWORK_CONFIG = @{
    ServiceType       = "NodePort"  # Options: ClusterIP, NodePort, LoadBalancer
    HTTPPort          = 30080
    HTTPSPort         = 30443
    NodeIP            = "192.168.1.100"  # Windows host IP
    LoadBalancerIP    = $null       # For cloud providers
}
# EndRegion

# Region: Storage Configuration
$STORAGE_CONFIG = @{
    PersistentStorage = $true
    PVC = @{
        Postgres      = "gitlab-postgres-pvc"
        Redis         = "gitlab-redis-pvc"
        RepoData      = "gitlab-data-pvc"
        Size          = "20Gi"      # Default size for all PVCs
        AccessModes   = @("ReadWriteOnce")
    }
    LocalPaths = @{
        Backup        = "C:\gitlab-backups"
        Config        = "C:\gitlab-config"
    }
}
# EndRegion

# Region: Offline Configuration
$OFFLINE_CONFIG = @{
    AirGapped         = $true
    LocalRegistry     = "registry.offline.local:5000"
    PreloadedImages   = @(
        "gitlab/gitlab-ce:15.9.3",
        "postgres:13.6",
        "redis:6.2-alpine",
        "prom/prometheus:v2.37.0",
        "grafana/grafana:9.1.2"
    )
    HelmDependencies  = @(
        "cert-manager-1.11.0.tgz",
        "nginx-1.5.1.tgz"
    )
}
# EndRegion

# Region: Logging and Monitoring
$LOGGING_CONFIG = @{
    LogLevel          = "INFO"      # DEBUG, INFO, WARN, ERROR
    LogRetentionDays  = 30
    LogPath           = "C:\gitlab-logs"
    Monitoring = @{
        Enabled       = $true
        ScrapeInterval= "60s"
        Retention     = "15d"
    }
}
# EndRegion

# Region: Security Configuration
$SECURITY_CONFIG = @{
    PodSecurityPolicy = $false
    NetworkPolicy     = $true
    RBAC = @{
        Enabled       = $true
        AdminUser     = "gitlab-admin"
    }
    ImagePullSecrets = @(
        "offline-registry-creds"
    )
}
# EndRegion

# Region: External Services
$EXTERNAL_SERVICES = @{
    SMTP = @{
        Enabled       = $false
        Host          = "smtp.company.local"
        Port          = 25
        User          = ""
        Password      = ""
    }
    LDAP = @{
        Enabled       = $false
        Host          = "ldap.company.local"
        BaseDN        = "dc=company,dc=local"
    }
}
# EndRegion

# Region: Validation Checks
$VALIDATION = @{
    MinimumMemoryGB   = 8
    MinimumCPU        = 4
    RequiredPorts     = @(80, 443, 22, 30080, 30443)
    OSVersion         = "10.0.17763"  # Windows 2019 LTSC
}
# EndRegion

# Export all configurations (PowerShell 5.1+ compatible)
Export-ModuleMember -Variable *