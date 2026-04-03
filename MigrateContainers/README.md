# FSLogix Profile Container Migration Scripts

A collection of PowerShell scripts for migrating FSLogix user profile containers between different storage platforms with VHD/VHDX conversion, ACL management, and comprehensive logging.

## 📋 Overview

This repository provides two specialized migration scripts, each optimized for different storage scenarios:

1. **[Migrate-Containers.ps1](README-AzureFiles.md)** - For **Azure Files** migrations
2. **[Migrate-Containers-Generic.ps1](README-Generic.md)** - For **generic UNC paths** (Azure NetApp Files, file servers, DFS, etc.)

Both scripts share common functionality through the `FSLogixMigrationCommon.psm1` module and provide:

✅ VHD to VHDX conversion (or VHD to dynamic VHD optimization)  
✅ Automatic ACL configuration with Creator Owner permissions  
✅ Optional folder renaming (SID_username ↔ username_SID)  
✅ Comprehensive logging and error handling  
✅ Progress tracking and CSV result exports  

## 🎯 Which Script Should I Use?

Use this decision guide to choose the right script for your migration scenario:

### Use **Migrate-Containers.ps1** (Azure Files) when:

✅ Migrating **between Azure Storage Accounts**  
✅ Migrating **between Azure Files shares** (same or different accounts)  
✅ You have **Azure PowerShell module (Az)** available  
✅ You want to use **Azure RBAC** (Entra ID) or **Storage Account Keys** for authentication  
✅ You want **AzCopy** for Azure-optimized transfers with concurrency  
✅ Your destination is clearly Azure Files  

**Example Scenarios:**
- Azure Files → Azure Files (cross-region)
- Azure Files Storage Account A → Storage Account B
- On-premises → Azure Files (with Azure PowerShell setup)

**[View Azure Files Documentation →](README-AzureFiles.md)**

---

### Use **Migrate-Containers-Generic.ps1** (Generic UNC) when:

✅ Migrating **to/from Azure NetApp Files (ANF)**  
✅ Migrating **between Windows File Servers**  
✅ Migrating **using DFS namespaces**  
✅ You **don't have** or **prefer not to use** Azure PowerShell module  
✅ You want to use **PSCredential** or **current Windows identity** for authentication  
✅ You want **Robocopy** with multi-threading for transfers  
✅ Working with any SMB share accessible via UNC path  

**Example Scenarios:**
- Azure NetApp Files → Azure NetApp Files
- File Server → Azure NetApp Files
- File Server → File Server
- DFS → Azure NetApp Files
- On-premises → any SMB share

**[View Generic UNC Documentation →](README-Generic.md)**

---

## 📊 Feature Comparison

| Feature | Azure Files Script | Generic UNC Script |
|---------|-------------------|-------------------|
| **Destination Types** | Azure Files only | Any SMB share (ANF, file servers, DFS, NAS) |
| **Authentication** | Entra ID (RBAC), Storage Keys | Windows identity, PSCredential |
| **Transfer Tool** | AzCopy or Direct UNC | Robocopy (multi-threaded) |
| **Required Modules** | Az PowerShell | None (uses native Windows tools) |
| **Azure Integration** | Full (storage account, keys, endpoints) | None (works with any UNC path) |
| **Concurrent Processing** | Yes (AzCopy) | Yes (PowerShell runspaces) |
| **Network Requirements** | Azure connectivity (443, 445) | SMB connectivity (445) |
| **Best Performance** | Same Azure region | Same network segment |
| **Cross-Cloud Support** | Azure Commercial, Gov, China | Any SMB-accessible location |

## 🚀 Quick Start

### Installation

1. **Clone the repository:**

```powershell
git clone https://github.com/shawntmeyer/FSLogix.git
cd FSLogix\MigrateContainers
```

2. **Verify you have the required files:**

```powershell
Get-ChildItem -Path . -Filter "*.ps1","*.psm1"

# You should see:
# - Migrate-Containers.ps1          (Azure Files script)
# - Migrate-Containers-Generic.ps1  (Generic UNC script)
# - FSLogixMigrationCommon.psm1     (Shared functions)
```

3. **Install prerequisites:**

```powershell
# Hyper-V PowerShell module (required by both scripts)
Install-WindowsFeature -Name Hyper-V-PowerShell -IncludeManagementTools

# Azure PowerShell module (only for Azure Files script)
Install-Module -Name Az -Repository PSGallery -Force

# AzCopy (optional, only for Azure Files script concurrent processing)
# Download from https://aka.ms/downloadazcopy
```

### Quick Examples

#### Azure Files Migration

```powershell
# Login to Azure
Connect-AzAccount

# Migrate between Azure Storage Accounts
.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "oldstorageaccount" `
    -SourceShareName "profiles" `
    -DestStorageAccountName "newstorageaccount" `
    -DestShareName "profiles"
```

#### Generic UNC Migration

```powershell
# Migrate between any UNC paths (e.g., Azure NetApp Files)
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\fileserver\profiles" `
    -DestinationUNCPath "\\10.0.1.10\anf-profiles"
```

## 📁 Repository Structure

```
MigrateContainers/
├── README.md                         # This file (decision guide)
├── README-AzureFiles.md              # Azure Files script documentation
├── README-Generic.md                 # Generic UNC script documentation
├── Migrate-Containers.ps1            # Azure Files migration script
├── Migrate-Containers-Generic.ps1    # Generic UNC migration script
├── FSLogixMigrationCommon.psm1       # Shared function module
└── Logs/                             # Auto-created log directory
```

## 🔍 Common Use Cases

### Use Case 1: Azure Files to Azure Files (Same Region)

**Scenario**: Migrating between storage accounts in the same Azure region

**Recommended Script**: `Migrate-Containers.ps1` (Azure Files)

**Why**: Azure-optimized with Entra ID authentication, fast transfers within region

**Example**:
```powershell
Connect-AzAccount
.\Migrate-Containers.ps1 -SourceStorageAccountName "oldsa" -SourceShareName "profiles" `
    -DestStorageAccountName "newsa" -DestShareName "profiles" -UseAzCopy -ConcurrentJobs 8
```

---

### Use Case 2: On-premises File Server to Azure NetApp Files

**Scenario**: Migrating from Windows file server to ANF as part of Azure adoption

**Recommended Script**: `Migrate-Containers-Generic.ps1`

**Why**: Works with any UNC path, no Azure PowerShell required, Robocopy handles SMB well

**Example**:
```powershell
.\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\onprem-fs\profiles" `
    -DestinationUNCPath "\\10.0.1.10\profiles" -ConcurrentProfiles 4 -RobocopyThreads 8
```

---

### Use Case 3: Azure Files to Azure NetApp Files

**Scenario**: Moving from Azure Files to ANF for higher performance/features

**Recommended Script**: `Migrate-Containers-Generic.ps1`

**Why**: ANF is accessed via UNC path, not Azure Storage API. Generic script is appropriate.

**Example**:
```powershell
# Map Azure Files using Entra ID or storage key first
$sourceCred = Get-Credential
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\storageaccount.file.core.windows.net\profiles" `
    -DestinationUNCPath "\\10.0.1.10\anf-profiles" `
    -SourceCredential $sourceCred
```

---

### Use Case 4: Cross-Region Azure Files Migration

**Scenario**: Migrating profiles from one Azure region to another (e.g., East US to West Europe)

**Recommended Script**: `Migrate-Containers.ps1` (Azure Files)

**Why**: AzCopy handles cross-region efficiently, Azure-native authentication

**Example**:
```powershell
Connect-AzAccount
azcopy login
.\Migrate-Containers.ps1 -SourceStorageAccountName "useast-sa" -SourceShareName "profiles" `
    -DestStorageAccountName "westeu-sa" -DestShareName "profiles" `
    -UseAzCopy -ConcurrentJobs 8
```

---

### Use Case 5: DFS Namespace to Azure NetApp Files

**Scenario**: Migrating from DFS namespace to ANF

**Recommended Script**: `Migrate-Containers-Generic.ps1`

**Why**: DFS is a UNC path, no Azure-specific features needed

**Example**:
```powershell
.\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\contoso.com\dfs\profiles" `
    -DestinationUNCPath "\\10.0.1.10\profiles" -RenameFolders
```

---

### Use Case 6: In-Place VHD Optimization (Any Platform)

**Scenario**: Converting existing VHD to dynamic VHD format to reclaim space

**Recommended Script**: Either (depends on storage type)

**Example (Azure Files)**:
```powershell
Connect-AzAccount
.\Migrate-Containers.ps1 -SourceStorageAccountName "sa1" -SourceShareName "profiles" -OutputType VHD
```

**Example (Generic UNC)**:
```powershell
.\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\server\profiles" -OutputType VHD
```

## ⚙️ Common Parameters

Both scripts share many common parameters:

| Parameter | Azure Files Script | Generic Script | Description |
|-----------|-------------------|----------------|-------------|
| **Source Location** | `-SourceStorageAccountName` + `-SourceShareName` | `-SourceUNCPath` | Source profile location |
| **Destination Location** | `-DestStorageAccountName` + `-DestShareName` | `-DestinationUNCPath` | Destination location |
| **Authentication** | `-UseStorageKey` (or Entra ID default) | `-SourceCredential` / `-DestinationCredential` | How to authenticate |
| **Output Format** | `-OutputType` (VHD\|VHDX) | `-OutputType` (VHD\|VHDX) | Output VHD format |
| **Folder Renaming** | `-RenameFolders` | `-RenameFolders` | SID_user → user_SID |
| **Concurrency** | `-UseAzCopy -ConcurrentJobs` | `-ConcurrentProfiles` | Parallel processing |
| **Logging** | `-LogPath` | `-LogPath` | Log file location |
| **ACL Config** | `-AdministratorGroupSIDs` / `-UserGroupSIDs` | `-AdministratorGroupSIDs` / `-UserGroupSIDs` | Custom ACL SIDs |

## 📝 Prerequisites

### Both Scripts Require:

- ✅ Windows Server 2019+ or Windows 10/11 Pro/Enterprise
- ✅ PowerShell 5.1 or later
- ✅ Hyper-V PowerShell module (`Install-WindowsFeature -Name Hyper-V-PowerShell`)
- ✅ Administrative privileges (for ACL operations and VHD conversion)
- ✅ Network connectivity to source and destination (port 445 for SMB)

### Azure Files Script Additionally Requires:

- ✅ Azure PowerShell module (`Install-Module -Name Az`)
- ✅ Azure subscription access
- ✅ Entra ID authentication OR Storage Account Key permissions
- ✅ Optional: AzCopy for concurrent processing (`https://aka.ms/downloadazcopy`)

### Generic UNC Script Additionally Requires:

- ✅ SMB access to source and destination shares
- ✅ Optional: PSCredential if not using current Windows identity
- ✅ Robocopy (built-in with Windows)

## 🛡️ Security & Best Practices

### Before Any Migration:

1. **Test First**: Always test with 2-5 profiles before full migration
2. **Backup**: Ensure source profiles are backed up
3. **Document**: Record SIDs used for custom ACLs
4. **Plan Downtime**: Schedule during maintenance window
5. **Verify Access**: Confirm read/write permissions to all shares

### Authentication Best Practices:

**Azure Files Script:**
- ✅ Prefer Entra ID (RBAC) over Storage Keys
- ✅ Assign "Storage File Data SMB Share Elevated Contributor" role
- ✅ Use `Connect-AzAccount` before running script

**Generic UNC Script:**
- ✅ Use current Windows identity when possible
- ✅ Use dedicated service account with minimal permissions
- ✅ Secure PSCredential objects (don't store plaintext passwords)

### After Migration:

1. **Verify Profiles**: Spot check that profiles load correctly
2. **Update FSLogix Settings**: Point FSLogix registry to new location
3. **Test User Logins**: Have test users verify profile functionality
4. **Monitor**: Watch for issues in FSLogix logs
5. **Cleanup**: Keep source profiles for 30+ days before deletion

## 📖 Documentation Links

- **Azure Files Script**: [README-AzureFiles.md](README-AzureFiles.md) - Full documentation for Azure Files migrations
- **Generic UNC Script**: [README-Generic.md](README-Generic.md) - Full documentation for generic UNC path migrations
- **FSLogix Documentation**: [Microsoft Learn](https://learn.microsoft.com/en-us/fslogix/)
- **Azure Files**: [Azure Files Documentation](https://learn.microsoft.com/en-us/azure/storage/files/)
- **Azure NetApp Files**: [ANF Documentation](https://learn.microsoft.com/en-us/azure/azure-netapp-files/)

## ❓ FAQ

**Q: Can I use the Azure Files script for Azure NetApp Files?**  
A: No. Azure NetApp Files is accessed via a standard UNC path and doesn't use the Azure Storage API. Use the Generic UNC script instead.

**Q: Which script is faster?**  
A: Performance depends more on your network and storage than the script choice. Both support parallelism. Azure Files with AzCopy can be faster for Azure Files to Azure Files migrations. Generic with Robocopy is optimized for any SMB share.

**Q: Do these scripts delete source profiles?**  
A: No. Source profiles are never deleted (except in-place VHD optimization, where originals are backed up first).

**Q: Can I migrate from Azure Files to a file server?**  
A: Yes, use the Generic UNC script. Azure Files can be accessed as a UNC path.

**Q: What if I need to migrate across domains?**  
A: Use the Generic UNC script with `-SourceCredential` and `-DestinationCredential` parameters to specify credentials for each domain.

**Q: How do I handle large migrations (500+ profiles)?**  
A: Use concurrent processing (`-UseAzCopy -ConcurrentJobs 8` for Azure Files, or `-ConcurrentProfiles 8` for Generic). Consider splitting into batches if system resources are limited.

**Q: Can I change folder naming during migration?**  
A: Yes, both scripts support `-RenameFolders` to convert between SID_username and username_SID formats.

**Q: What happens if the script is interrupted?**  
A: The script doesn't support resume. Re-run it, and it will process all profiles again (already migrated profiles will be overwritten). Consider migrating in smaller batches.

## 🐛 Troubleshooting

### Common Issues Across Both Scripts:

1. **"Hyper-V module not found"**
   - Install: `Install-WindowsFeature -Name Hyper-V-PowerShell`
   - Requires restart

2. **"Access Denied" errors**
   - Run PowerShell as Administrator
   - Verify share permissions
   - Check NTFS permissions
   - For Azure Files: Verify RBAC role or storage key access

3. **Slow performance**
   - Increase concurrency settings
   - Check network bandwidth
   - Verify storage isn't throttled
   - Reduce concurrency if CPU/memory limited

4. **Out of disk space**
   - Free up space in temp directory
   - Change `-TempPath` to larger drive
   - Migrate in smaller batches

### Script-Specific Issues:

**Azure Files Script:**
- **"Storage account not found"**: Verify account name, ensure `Connect-AzAccount` was run
- **"AzCopy not authenticated"**: Run `azcopy login` before script
- **Storage endpoint errors**: May be using Azure Government/China, script will auto-detect

**Generic UNC Script:**
- **"Cannot access UNC path"**: Verify network connectivity, DNS resolution, firewall (port 445)
- **Authentication failures**: Use `-SourceCredential` / `-DestinationCredential` with valid credentials
- **Robocopy errors**: Check `Robocopy_*.log` files in LogPath for details

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test thoroughly with multiple scenarios
4. Update relevant documentation
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

**This sample code is provided for illustration purposes only and is not intended to be used in a production environment without thorough testing.** The code is provided "AS IS" without warranty of any kind, either expressed or implied, including but not limited to the implied warranties of merchantability and/or fitness for a particular purpose. Always test in a non-production environment before deploying to production systems.

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/shawntmeyer/FSLogix/issues)
- **Pull Requests**: [GitHub PRs](https://github.com/shawntmeyer/FSLogix/pulls)
- **Documentation**: [FSLogix Microsoft Learn](https://learn.microsoft.com/en-us/fslogix/)

---

**Last Updated**: April 3, 2026  
**Repository**: [https://github.com/shawntmeyer/FSLogix](https://github.com/shawntmeyer/FSLogix)  
**Maintainer**: Shawn Meyer
