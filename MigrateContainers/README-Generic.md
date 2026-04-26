# FSLogix Profile Migration Script (Generic UNC Paths)

A comprehensive PowerShell script for migrating FSLogix user profile containers between **any SMB file shares** including Azure NetApp Files, Windows File Servers, DFS namespaces, and other UNC paths. Performs VHD/VHDX conversion, ACL management, and optional folder renaming with concurrent PowerShell-based file transfers.

## ⚠️ Disclaimer

**This sample code is provided for illustration purposes only and is not intended for production use without thorough testing.** The code is provided "AS IS" without warranty of any kind. See the full disclaimer in the script header for complete terms. Always test in a non-production environment before deploying to production systems.

## Overview

This script automates the migration of FSLogix profile containers (VHD/VHDX files) between any SMB-accessible file shares while:

- Converting VHD to dynamic VHDX format (or optimizing VHD to dynamic VHD)
- Setting proper NTFS permissions and ownership
- Optionally renaming folders from `SID_username` to `username_SID` format
- Concurrent profile-level parallelism with PowerShell runspaces
- Comprehensive logging and progress tracking

## Features

✅ **Universal Support**: Works with Azure NetApp Files, Windows File Servers, DFS, NAS appliances  
✅ **Format Conversion**: VHD → VHDX or VHD → Dynamic VHD  
✅ **Concurrent Processing**: Parallel profile migrations via PowerShell runspaces  
✅ **Folder Renaming**: Change from SID_username to username_SID format  
✅ **ACL Management**: Automatically set ownership and permissions  
✅ **Flexible Authentication**: Current Windows identity or PSCredential  
✅ **Comprehensive Logging**: Console output + detailed log files + CSV results  
✅ **Progress Tracking**: Real-time progress indicators  
✅ **Error Handling**: Graceful error handling with detailed reporting  

## Prerequisites

### Required Software

| Component | Version | Installation |
| --------- | ------- | ------------ |
| **PowerShell** | 5.1 or later | Pre-installed on Windows |
| **Hyper-V PowerShell Module** | Latest | `Install-WindowsFeature -Name Hyper-V-PowerShell` |

### Permissions

**Required Access:**
- Read permissions on source share and all profile folders
- Write permissions on destination share
- Ability to set ownership and ACLs (typically requires administrative privileges)

**Running the Script:**
- Run PowerShell as Administrator (required for ACL operations and VHD conversion)
- Ensure the executing account has appropriate permissions to both shares

### Network Requirements

- **Port 445**: SMB access to source and destination shares
- **Bandwidth**: 1Gbps recommended for large migrations
- **Same Network**: Best performance when server is in same network segment as shares
- **VPN**: If accessing remote shares, ensure stable VPN connection

## Installation

1. **Download the script and common module:**

```powershell
git clone https://github.com/shawntmeyer/FSLogix.git
cd FSLogix\MigrateContainers
```

2. **Verify required files are present:**

```powershell
# You should have these files:
# - Migrate-Containers-Generic.ps1
# - Modules\FSLogixMigration.psm1
Get-ChildItem -Path . -Filter "*.ps1","*.psm1" -Recurse
```

3. **Install Hyper-V PowerShell module (if not already installed):**

```powershell
# Requires restart
Install-WindowsFeature -Name Hyper-V-PowerShell -IncludeManagementTools
```

4. **Verify installation:**

```powershell
# Test Hyper-V module
Get-Module -ListAvailable -Name Hyper-V
```

## Usage

### Basic Syntax

```powershell
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath <string> `
    [-DestinationUNCPath <string>] `
    [-SourceCredential <PSCredential>] `
    [-DestinationCredential <PSCredential>] `
    [-OutputType <VHD|VHDX>] `
    [-RenameFolders <bool>] `
    [-ConcurrentProfiles <int>]
```

### Example Scenarios

#### 1. Simple Migration (Current Windows Identity)

**Scenario**: Migrate profiles between two file servers using your current credentials

```powershell
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\oldserver\profiles" `
    -DestinationUNCPath "\\newserver\profiles"
```

**Expected Time**: ~2-3 minutes per 10GB profile (sequential)

---

#### 2. Azure NetApp Files Migration

**Scenario**: Migrate from on-premises file server to Azure NetApp Files

```powershell
# ANF typically accessed via IP address
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\fileserver.contoso.com\profiles" `
    -DestinationUNCPath "\\10.0.1.10\profiles"
```

**Note**: Ensure network connectivity to ANF private endpoint/subnet

---

#### 3. Migration with Explicit Credentials

**Scenario**: Migrating across domains or when current identity lacks permissions

```powershell
# Prompt for credentials
$srcCred = Get-Credential -Message "Enter credentials for source share"
$dstCred = Get-Credential -Message "Enter credentials for destination share"

.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\olddomain\profiles" `
    -DestinationUNCPath "\\newdomain\profiles" `
    -SourceCredential $srcCred `
    -DestinationCredential $dstCred
```

---

#### 4. High-Performance Migration with Concurrency

**Scenario**: Migrate 100+ profiles quickly using parallel processing

```powershell
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\source\profiles" `
    -DestinationUNCPath "\\dest\profiles" `
    -ConcurrentProfiles 8
```

**Expected Time**: ~30-45 minutes for 100x10GB profiles

---

#### 5. In-Place VHD Optimization

**Scenario**: Optimize existing VHD files to dynamic VHD format (reclaim space)

```powershell
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\fileserver\profiles" `
    -OutputType VHD
```

**Note**: Original VHD is backed up as `.vhd.backup` during conversion

---

#### 6. Migration with Folder Renaming

**Scenario**: Change folder naming convention from `SID_username` to `username_SID`

```powershell
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\oldserver\profiles" `
    -DestinationUNCPath "\\newserver\profiles" `
    -RenameFolders $true
```

**Before**: `S-1-5-21-xxx_jdoe`  
**After**: `jdoe_S-1-5-21-xxx`

---

#### 7. DFS Namespace Migration

**Scenario**: Migrate profiles between DFS namespace targets

```powershell
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\contoso.com\dfs\profiles-old" `
    -DestinationUNCPath "\\contoso.com\dfs\profiles-new"
```

---

#### 8. Custom Administrator Groups for ACLs

**Scenario**: Grant specific domain admin groups full control

```powershell
.\Migrate-Containers-Generic.ps1 `
    -SourceUNCPath "\\server\profiles" `
    -DestinationUNCPath "\\newserver\profiles" `
    -AdministratorGroupSIDs @('S-1-5-32-544', 'S-1-5-21-xxx-512')
```

## Parameters Reference

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `SourceUNCPath` | String | - | **Yes** | Source UNC path (e.g., `\\server\share`) |
| `DestinationUNCPath` | String | Same as source | No | Destination UNC path |
| `SourceCredential` | PSCredential | Current identity | No | Credentials for source share |
| `DestinationCredential` | PSCredential | Current identity | No | Credentials for destination share |
| `OutputType` | String | `VHDX` | No | Output format: `VHD` or `VHDX` |
| `RenameFolders` | Bool | `$false` | No | Rename SID_user to user_SID (`$true`/`$false`) |
| `ConcurrentProfiles` | Int | `4` | No | Number of parallel profile migrations |
| `LogPath` | String | `.\Logs` | No | Directory for log files |
| `TempPath` | String | `$env:TEMP\FSLogixMigration` | No | Temp directory for VHD conversion |
| `AdministratorGroupSIDs` | String[] | `@('S-1-5-32-544')` | No | Admin group SIDs for ACLs |
| `UserGroupSIDs` | String[] | `@()` | No | User group SIDs for ACLs |

## Performance Considerations

### Profile-level Concurrency

**ConcurrentProfiles Parameter:**
- Controls how many profiles are migrated **simultaneously**
- Each concurrent job runs its own VHD conversion + Copy-Item operation
- **Recommended**: 2-8 depending on resources

**Resource Requirements:**

| Concurrent Profiles | CPU Usage | Memory | Disk I/O | Recommended For |
| ------------------- | --------- | ------ | -------- | --------------- |
| 1 | Low | ~2GB | Low | Small migrations, low-end systems |
| 2-4 | Medium | ~4-6GB | Medium | Most scenarios (balanced) |
| 4-8 | High | ~8-12GB | High | Large migrations, powerful systems |
| 8+ | Very High | ~16GB+ | Very High | Special cases only |

### Performance Estimates

**Network-bound scenarios (1Gbps):**
- Sequential (1 profile): ~2-3 min per 10GB
- Concurrent (4 profiles): ~45-60 sec per 10GB per profile
- Concurrent (8 profiles): ~30-40 sec per 10GB per profile

**100 Profiles @ 10GB each:**
- Sequential: ~4-5 hours
- Concurrent (4): ~60-80 minutes
- Concurrent (8): ~40-50 minutes

**Note**: Actual times vary based on network, storage, VHD fragmentation, and CPU

## Output and Logging

### Console Output

Real-time progress with color-coded messages:

- **Green**: Success operations
- **Yellow**: Warnings
- **Red**: Errors
- **White**: Information

### Log Files

Located in `LogPath` (default: `.\Logs\`):

1. **Main Log**: `FSLogixMigration_Generic_YYYYMMDD_HHMMSS.log`
   - Detailed timestamped log of all operations
   - Includes debug information
   - Used for troubleshooting

2. **Results CSV**: `MigrationResults_Generic_YYYYMMDD_HHMMSS.csv`
   - Summary of each profile migration
   - Columns: SourceFolder, DestFolder, SourceVHD, DestOutput, OriginalSize, ConvertedSize, Success, Error
   - Import into Excel for analysis

### Example Output

```
[2026-04-03 10:00:00] [INFO] FSLogix Profile Migration Script (Generic UNC)
[2026-04-03 10:00:00] [INFO] Source: \\oldserver\profiles
[2026-04-03 10:00:00] [INFO] Destination: \\newserver\profiles
[2026-04-03 10:00:00] [SUCCESS] Source share accessible
[2026-04-03 10:00:00] [SUCCESS] Destination share accessible
[2026-04-03 10:00:05] [SUCCESS] Found 100 VHD files to migrate
[2026-04-03 10:00:10] [INFO] Starting migration for: S-1-5-21-xxx_jdoe
[2026-04-03 10:02:05] [SUCCESS] Conversion successful. VHDX size: 8.23 GB
[2026-04-03 10:02:08] [SUCCESS] Migration completed successfully
...
[2026-04-03 12:30:15] [INFO] Migration Summary
[2026-04-03 12:30:15] [SUCCESS] Total Profiles: 100
[2026-04-03 12:30:15] [SUCCESS] Successful: 100
[2026-04-03 12:30:15] [INFO] Failed: 0
[2026-04-03 12:30:15] [INFO] Duration: 02:30:10
```

## ACL Configuration

The script automatically configures NTFS permissions on migrated profiles:

### Share Root Permissions

Applied when migrating to a **new** destination:

| Principal | Permission | Applies To |
| --------- | ---------- | ---------- |
| SYSTEM | Full Control | This folder, subfolders, and files |
| Administrators* | Full Control | This folder, subfolders, and files |
| Creator Owner | Full Control | Subfolders and files only |
| Authenticated Users** | Modify | This folder only |

*Configurable via `-AdministratorGroupSIDs`  
**Configurable via `-UserGroupSIDs` (or custom groups)

### Profile Folder Permissions

For each profile folder:

1. **Ownership** set to user (based on SID extracted from folder name)
2. **Inheritance enabled** from share root
3. **Creator Owner permissions** automatically apply to the owner

**Result**: User gets full control of their profile via Creator Owner inheritance

## Troubleshooting

### Common Issues

#### Access Denied Errors

**Symptom**: `Access is denied` when accessing shares or setting ACLs

**Solutions**:

1. Run PowerShell as Administrator
2. Verify credentials have appropriate permissions
3. Check NTFS permissions on source/destination shares
4. Ensure account has "Take ownership" privilege
5. Use `-SourceCredential` / `-DestinationCredential` if needed

```powershell
# Test access manually
Test-Path "\\server\share"

# Try with credentials
$cred = Get-Credential
New-PSDrive -Name "T" -PSProvider FileSystem -Root "\\server\share" -Credential $cred
```

#### Hyper-V Module Not Found

**Symptom**: `Module Hyper-V not found`

**Solution**:

```powershell
# Install Hyper-V PowerShell module
Install-WindowsFeature -Name Hyper-V-PowerShell -IncludeManagementTools

# Verify installation
Get-Module -ListAvailable -Name Hyper-V
```

**Note**: Requires Windows Server or Windows 10/11 Pro/Enterprise

#### Network Connectivity Issues

**Symptom**: Cannot access UNC path, slow transfers, or timeouts

**Solutions**:

1. Test SMB connectivity:

```powershell
Test-NetConnection -ComputerName "server.contoso.com" -Port 445
```

2. Verify DNS resolution:

```powershell
Resolve-DnsName "server.contoso.com"
```

3. Check firewall rules (port 445 must be open)
4. Verify SMB signing requirements match between client and server
5. For Azure NetApp Files: Ensure VM is in VNet with connectivity to ANF subnet

#### Slow Performance

**Symptom**: Migration taking longer than expected

**Solutions**:

1. Increase concurrent profiles: `-ConcurrentProfiles 8`
2. Check network bandwidth: `Test-NetConnection -ComputerName server -Port 445 -InformationLevel Detailed`
4. Verify storage is not bottleneck (check IOPS/throughput limits)
5. Reduce concurrency if CPU/memory constrained
6. For ANF: Check volume throughput tier limits

#### Out of Disk Space

**Symptom**: Error during VHD conversion - insufficient disk space

**Solutions**:

1. Free up space in temp directory
2. Change temp path to larger drive: `-TempPath "D:\Temp"`
3. Migrate in smaller batches
4. Clean up temp files from failed migrations

## Best Practices

### Before Migration

1. **Test First**: Run with 2-5 test profiles before full migration
2. **Verify Access**: Confirm you can read/write to both shares
3. **Check Network**: Ensure stable connectivity and adequate bandwidth
4. **Plan Downtime**: Schedule during maintenance window
5. **Backup**: Ensure source profiles are backed up (script doesn't delete source)
6. **Document SIDs**: If using custom admin/user groups, document SIDs used
7. **Disk Space**: Ensure temp drive has 2x space of largest profile

### During Migration

1. **Monitor Progress**: Watch console output and log files
2. **Check Resources**: Monitor CPU, memory, disk, and network usage
3. **Verify Network**: Ensure stable connection throughout
4. **Spot Check**: Periodically verify migrated profiles are accessible
5. **Don't Interrupt**: Let script complete fully (profiles are tracked individually)

### After Migration

1. **Verify ACLs**: Spot check permissions on migrated profiles
2. **Test Access**: Have test users log in to verify profiles work
3. **Review Logs**: Check for any warnings or errors
4. **Update FSLogix**: Point FSLogix to new storage location (see FSLogix Configuration section below)
5. **Monitor**: Watch for user login issues
6. **Cleanup**: Remove old profiles after confirming migration success (wait 30+ days)

## FSLogix Configuration Updates

After migrating profiles, you must update FSLogix registry settings to reflect the new storage location and profile format.

### Required Registry Settings

FSLogix settings are located at:
- **Registry Path**: `HKLM\SOFTWARE\FSLogix\Profiles`
- **Group Policy**: Computer Configuration → Policies → Administrative Templates → FSLogix

### Settings That Must Be Updated

#### 1. VHDLocations (Critical)

**When to Update**: Always update if migrating to a different share path.

**Registry Key**: `VHDLocations`  
**Type**: `REG_MULTI_SZ` or `REG_SZ`  

**Before Migration Example:**
```
\\oldserver\profiles
```

**After Migration Example:**
```
\\newserver\profiles
```

**PowerShell Update:**
```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "VHDLocations" `
    -Value "\\newserver\profiles" `
    -Type MultiString
```

**For Azure NetApp Files:**
```powershell
# ANF typically uses IP address
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "VHDLocations" `
    -Value "\\10.0.1.10\profiles" `
    -Type MultiString
```

#### 2. VolumeType (If Changed to VHDX)

If you migrated from VHD to VHDX format:

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "VolumeType" `
    -Value "VHDX" `
    -Type String
```

#### 3. IsDynamic (Dynamic vs Fixed)

This script creates **dynamic** disks. Ensure this matches:

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "IsDynamic" `
    -Value 1 `
    -Type DWord
```

#### 4. FlipFlopProfileDirectoryName (If Using RenameFolders)

If you used `-RenameFolders` to change to username_SID format:

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "FlipFlopProfileDirectoryName" `
    -Value 1 `
    -Type DWord
```

### Verification

After updating settings:

```powershell
# Verify registry values
Get-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" | Format-List

# Test share access from session host
Test-Path "\\newserver\profiles"

# Check FSLogix logs after user login
Get-Content "C:\ProgramData\FSLogix\Logs\Profile\*.log" -Tail 50
```

## Security Considerations

### Authentication

- **Current Identity**: Most convenient, uses Kerberos/NTLM
- **PSCredential**: Allows cross-domain or specific account usage
- **Principle of Least Privilege**: Use dedicated migration account with minimal required permissions

### Data in Transit

- SMB 3.x encryption (if supported by file server)
- For Azure NetApp Files: SMB 3.0+ with encryption enabled by default
- Consider VPN or ExpressRoute for cross-region/cloud migrations

### Permissions

- Script requires elevated privileges for ACL operations
- Run from secure administrative workstation
- Use Jump Box for isolated migration environment
- Audit who has access to run migrations

### Logging

- Logs contain profile folder names (may include usernames)
- Store logs securely with appropriate ACLs
- Review access to log directories
- Consider log retention policies and compliance requirements

## Limitations

- **Windows Only**: Requires Windows OS with Hyper-V PowerShell module
- **VHD/VHDX Only**: Only processes VHD/VHDX files (not other profile types)
- **SMB Required**: Destination must be SMB-accessible (no NFS, object storage, etc.)
- **No Resume**: Failed profiles must be re-migrated (no checkpoint/resume)
- **Same VHDX Version**: Output VHDX version matches Convert-VHD defaults
- **No Dedupe**: Does not deduplicate data between profiles

## Comparison: Generic vs Azure Files Scripts

| Feature | Generic UNC Script | Azure Files Script |
|---------|-------------------|-------------------|
| **Destination** | Any SMB share (file servers, ANF, DFS) | Azure Files only |
| **Authentication** | Windows identity or PSCredential | Entra ID or Storage Keys |
| **Transfer Tool** | Copy-Item (PowerShell) | AzCopy or Direct UNC |
| **Azure Dependencies** | None | Az PowerShell module |
| **Best For** | Azure NetApp Files, file servers, hybrid | Pure Azure Files deployments |

**When to use this script:**
- Migrating to/from Azure NetApp Files
- Migrating between Windows File Servers
- DFS namespace migrations
- No Azure PowerShell module available
- No external tool dependencies (uses built-in PowerShell Copy-Item)

**When to use Azure Files script:**
- Migrating between Azure Storage Accounts
- Leveraging Azure RBAC for permissions
- Using AzCopy for Azure-optimized transfers

## FAQ

**Q: Does this work with Azure NetApp Files?**  
A: Yes! This is one of the primary use cases. Access ANF via UNC path (e.g., `\\10.0.1.10\volume`).

**Q: Will source profiles be deleted?**  
A: No. Source profiles remain untouched. For in-place VHD optimization, originals are backed up and only deleted after successful conversion.

**Q: Can this migrate from on-premises to Azure NetApp Files?**  
A: Yes, as long as the migration server has network connectivity to both the on-prem file server and ANF (via ExpressRoute, VPN, or internet).

**Q: How does this compare to AzCopy for Azure Files?**  
A: Copy-Item is sufficient for any SMB share and has no external dependencies. AzCopy is optimized for Azure Files specifically. Choose based on your destination: ANF or file servers = this script, Azure Files = the Azure Files script.

**Q: Can I pause and resume the migration?**  
A: No. The script processes profiles completely. If interrupted, re-run the script - it will process all profiles again.

**Q: Does this work with NFS?**  
A: No. The script requires SMB/CIFS shares accessible via UNC path.

## Support

- **Issues**: [GitHub Issues](https://github.com/shawn tmeyer/FSLogix/issues)
- **Documentation**: [FSLogix Docs](https://learn.microsoft.com/en-us/fslogix/)
- **Azure NetApp Files**: [ANF Docs](https://learn.microsoft.com/en-us/azure/azure-netapp-files/)

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

## License

This script is provided as-is under the MIT License. See LICENSE file for details.

## Changelog

### Version 1.0 (2026-04-03)

- Initial release
- Support for any UNC path (Azure NetApp Files, file servers, DFS, etc.)
- VHD to VHDX conversion
- VHD to dynamic VHD optimization
- PSCredential authentication support
- Concurrent profile-level processing via PowerShell runspaces
- ACL management with Creator Owner
- Folder renaming (SID_username ↔ username_SID)
- Comprehensive logging and reporting
- Utility function library (Modules\FSLogixMigration.psm1)

---

**Last Updated**: April 3, 2026  
**Tested On**: Windows Server 2019/2022, Windows 10/11 Pro/Enterprise  
**PowerShell Version**: 5.1, 7.x  
**Tested With**: Azure NetApp Files, Windows File Servers, DFS Namespaces
