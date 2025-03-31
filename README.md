# GitLab on Kubernetes Automation 🚀

<!--![GitLab Logo](https://about.gitlab.com/images/press/logo/png/gitlab-logo-500.png)-->
*Automated deployment of GitLab on Kubernetes (Docker Desktop/WSL2)*

## 📋 Table of Contents
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Solution Structure](#-solution-structure)
- [Configuration](#-configuration)
- [Deployment Scenarios](#-deployment-scenarios)
- [Offline Installation](#-offline-installation)
- [Maintenance](#-maintenance)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)

## ✨ Features
- **Turnkey GitLab Deployment**:
  - Single-command installation (`bootstrap.ps1`)
  - Configurable for minimal or production setups
- **Enterprise-Ready**:
  - Built-in SSL (Let's Encrypt or self-signed)
  - LDAP/SMTP integration
  - Automated backups
- **Modular Design**:
  - Loosely coupled PowerShell scripts
  - Centralized configuration (`variables.ps1`)
- **Multi-Environment Support**:
  - Works on Windows/WSL2/Docker Desktop
  - Air-gapped deployment capability

## 🛠 Prerequisites
| Component           | Requirement                          |
|---------------------|--------------------------------------|
| OS                  | Windows 10/11 (Build 19041+) with WSL2 enabled |
| Docker Desktop      | 4.12+ with Kubernetes enabled       |
| Kubernetes          | 1.24+ (Docker Desktop default)      |
| PowerShell          | 7.2+ (Admin privileges)             |
| Hardware            | 8GB+ RAM, 4+ CPU cores, 50GB disk   |

> 💡 **Tip**: Run `.\scripts\01_setup_environment.ps1 -validate` to check prerequisites.

## 🚀 Quick Start
```powershell
# Clone repository (if not using the generated structure)
git clone https://your-repo/gitlab-k8s-automation.git
cd gitlab-k8s-automation

# 1. Edit configuration (adjust domain, resources, etc.)
code variables.ps1

# 2. Run bootstrap (minimal profile)
.\scripts\bootstrap.ps1

# For production deployment:
.\scripts\bootstrap.ps1 -Profile production
```

**Access after deployment**:
- URL: `https://gitlab.yourdomain.local`
- Default credentials: `root/ChangeMe123!` *(change immediately!)*

## 📂 Solution Structure
```markdown
.
├── .vscode/             # VS Code settings
├── configs/             # Kubernetes manifests
├── offline-resources/   # Air-gapped assets
│   ├── charts/          # Helm charts
│   └── images/          # Container images
├── scripts/             # Automation scripts
│   ├── 01_setup_environment.ps1
│   ├── 02_install_kubernetes.ps1
│   ├── 03_deploy_gitlab.ps1
│   ├── 04_configure_gitlab.ps1
│   └── bootstrap.ps1
├── secrets/             # SSL certs & credentials
├── variables.ps1        # Central configuration
└── README.md            # This file
```

## ⚙️ Configuration
Key settings in `variables.ps1`:

```powershell
# Domain and Access
$GITLAB_CONFIG = @{
    Domain = "gitlab.company.local"
    InitialRootPassword = "SecurePassword123!" # Change this!
    SSL = @{
        Enabled = $true
        SelfSigned = $false # Set true for air-gapped
    }
}

# Resource Profiles
$RESOURCE_PROFILES = @{
    Minimal = @{  # For local development
        Web = @{ cpu="500m"; memory="2Gi" }
        Postgres = @{ cpu="1"; memory="4Gi" }
    }
    Production = @{  # For team usage
        Web = @{ cpu="2"; memory="8Gi" }
        Postgres = @{ cpu="4"; memory="16Gi" }
    }
}
```

## 🌐 Deployment Scenarios
### 1. **Local Development (Minimal)**
```powershell
.\bootstrap.ps1 -Profile minimal
```
- 1 replica per service
- Self-signed SSL
- No external integrations

### 2. **Production Deployment**
```powershell
.\bootstrap.ps1 -Profile production
```
- 3x web service replicas
- Let's Encrypt SSL
- SMTP and monitoring enabled

### 3. **Air-Gapped Environment**
1. Pre-download resources:
   ```powershell
   .\scripts\download-offline-resources.ps1
   ```
2. Transfer folder to target machine
3. Deploy:
   ```powershell
   .\bootstrap.ps1 -OfflineMode
   ```

## 📦 Offline Installation
**Required Resources**:
1. Container images (save as .tar):
   ```bash
   docker save -o gitlab-ce.tar gitlab/gitlab-ce:15.9.3
   ```
2. Helm charts:
   ```bash
   helm pull gitlab/gitlab --version 7.1.0
   ```
3. Place in:
   ```
   offline-resources/
   ├── charts/
   │   └── gitlab-7.1.0.tgz
   └── images/
       └── gitlab-ce-15.9.3.tar
   ```

### **👥 Contributing Guidelines**

We welcome contributions! Please follow these steps:

#### **1. Setting Up for Development**
```bash
# Fork and clone the repository
git clone https://github.com/zerocold2/gitlab-k8s-automation.git
cd gitlab-k8s-automation

# Install pre-commit hooks (recommended)
pip install pre-commit
pre-commit install
```

#### **2. Contribution Workflow**
1. **Branch Naming**:
   - `feature/`: New functionalities (e.g., `feature/smtp-auth`)
   - `fix/`: Bug fixes (e.g., `fix/helm-timeout`)
   - `docs/`: Documentation updates

2. **Commit Message Format**:
   ```
   type(scope): brief description
   
   Detailed explanation (if needed)
   ```
   Example:
   ```
   feat(scripts): add LDAP configuration to 04_configure_gitlab.ps1

   - Added LDAP template generation
   - Integrated with variables.ps1
   ```

#### **3. Quality Standards**
- **Scripts**: Must pass [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) checks
- **Helm Charts**: Pin versions in `variables.ps1`
- **Tests**: Add validation steps to `01_setup_environment.ps1` for new features

#### **4. Submitting Changes**
1. Open a Pull Request with:
   - Description of changes
   - Screenshots (for UI-related updates)
   - Updated documentation if applicable

2. Await review from maintainers (typically within 48 hours)

---

### **🕰 Version History**

| Version | Date       | Changes                          |
|---------|------------|----------------------------------|
| `1.2.0` | 2023-11-15 | Added air-gapped support         |
| `1.1.0` | 2023-10-20 | Production profile enhancements  |
| `1.0.0` | 2023-09-05 | Initial stable release           |

**Detailed Changelog**: [CHANGELOG.md](CHANGELOG.md)

---

## 🛠 Maintenance
### Backup/Restore
```powershell
# Manual backup
kubectl exec -n gitlab-system <gitlab-pod> -- gitlab-backup create

# Schedule backups (configured in 04_configure_gitlab.ps1)
# Runs daily at 2AM via Kubernetes CronJob
```

### Upgrade Version
1. Update `variables.ps1`:
   ```powershell
   $HELM_CONFIG.ChartVersion = "7.2.0"
   ```
2. Rerun deployment:
   ```powershell
   .\scripts\03_deploy_gitlab.ps1
   ```

## 🐛 Troubleshooting
| Issue                          | Solution                          |
|--------------------------------|-----------------------------------|
| Kubernetes not starting        | Restart Docker Desktop            |
| Helm timeouts                  | Increase `$HELM_CONFIG.Timeout`   |
| SSL errors                     | Verify certs in `secrets/ssl/`    |
| Low disk space                 | Clean up old backups              |

**View logs**:
```powershell
# Pod logs
kubectl logs -n gitlab-system deploy/gitlab-webservice

# Script execution logs
Get-Content .\logs\<timestamp>\*.log
```

## 📜 License
Apache 2.0 - See [LICENSE](LICENSE) for details.
---

> **Note**: Always change default credentials and review SSL configuration before production use.  
> For support, open an issue in our [GitHub repository](https://github.com/zerocold2/gitlab-k8s-automation).
