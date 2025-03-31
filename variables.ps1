<#
.SYNOPSIS
Central configuration file for GitLab on Kubernetes deployment
#>

# Kubernetes Cluster Configuration
`$KUBERNETES_CONFIG = @{
    ClusterName       = "gitlab-cluster"
    Context           = "docker-desktop"
    Namespace         = "gitlab-system"
    StorageClass      = "hostpath"
    EnableIngress     = `$true
    IngressController = "nginx"
}

# GitLab Core Configuration
`$GITLAB_CONFIG = @{
    Domain            = "gitlab.company.local"
    InitialRootPassword = "ChangeMe123"
    SSL = @{
        Enabled       = `$true
        SelfSigned    = `$true
        CertPath      = ".\ssl\gitlab.crt"
        KeyPath       = ".\ssl\gitlab.key"
    }
}

# Resource Allocation
`$RESOURCE_PROFILES = @{
    ActiveProfile     = "minimal"
    Minimal = @{
        Web = @{ cpu="500m"; memory="2Gi" }
        Postgres = @{ cpu="500m"; memory="2Gi"; storage="10Gi" }
    }
}
