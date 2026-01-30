# FSLogix Profile Migration Script

A comprehensive PowerShell script for migrating FSLogix user profile containers between Azure Storage Accounts and File Shares with VHD/VHDX conversion, ACL management, and optional folder renaming.

## ⚠️ Disclaimer

**This sample code is provided for illustration purposes only and is not intended for production use without thorough testing.** The code is provided "AS IS" without warranty of any kind. See the full disclaimer in the script header for complete terms. Always test in a non-production environment before deploying to production systems.

## Overview

This script automates the migration of FSLogix profile containers (VHD/VHDX files) between Azure File Shares while:

- Converting VHD to dynamic VHDX format (or optimizing VHD to dynamic VHD)
- Setting proper NTFS permissions and ownership
- Optionally renaming folders from `SID_username` to `username_SID` format
- Supporting both direct conversion and concurrent processing with AzCopy
- Providing comprehensive logging and progress tracking

## Features

✅ **Format Conversion**: VHD → VHDX or VHD → Dynamic VHD  
✅ **Cross-Account Migration**: Move profiles between storage accounts  
✅ **In-Place Optimization**: Convert profiles within same storage account  
✅ **Folder Renaming**: Change from SID_username to username_SID format  
✅ **ACL Management**: Automatically set ownership and permissions  
✅ **Dual Authentication**: Entra ID (recommended) or Storage Account Keys  
✅ **Concurrent Processing**: AzCopy with parallel jobs for faster migrations  
✅ **Comprehensive Logging**: Console output + detailed log files + CSV results  
✅ **Progress Tracking**: Real-time progress indicators  
✅ **Error Handling**: Graceful error handling with detailed reporting  
✅ **Multi-Cloud Support**: Works with Azure Commercial, Government, China

## Prerequisites

### Required Software

| Component | Version | Installation |
| --------- | ------- | ------------ |
| **PowerShell** | 5.1 or later | Pre-installed on Windows |
| **Hyper-V PowerShell Module** | Latest | `Install-WindowsFeature -Name Hyper-V-PowerShell` |
| **Azure PowerShell Module** | Latest | `Install-Module -Name Az -Repository PSGallery -Force` |
| **AzCopy** (optional) | v10 or later | [Download](https://aka.ms/downloadazcopy) |

### Azure Permissions

Choose ONE of the following authentication methods:

#### Option 1: Entra ID Authentication (Recommended)

**Required RBAC Role:**

- **Storage File Data SMB Share Elevated Contributor**
- **Role ID**: `a7264617-510b-434b-a828-9731dc254ea7`
- **Scope**: Both source AND destination storage accounts
- **Why**: Allows full NTFS permissions including ownership and ACL management

**How to Assign:**

```powershell
# Login to Azure
Connect-AzAccount

# Assign role to storage account
$storageAccount = Get-AzStorageAccount -ResourceGroupName "rg-name" -Name "storageaccount"
$userId = (Get-AzADUser -UserPrincipalName "user@domain.com").Id

New-AzRoleAssignment `
    -ObjectId $userId `
    -RoleDefinitionName "Storage File Data SMB Share Elevated Contributor" `
    -Scope $storageAccount.Id
```

[Learn more about Storage File RBAC roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-file-data-smb-share-elevated-contributor)

#### Option 2: Storage Account Key Authentication

**Required Permission:**

- Permission to read storage account keys
- Typically: Contributor, Storage Account Contributor, or Owner role on storage account

**Note**: Less secure than Entra ID but simpler to configure for testing.

### Network Requirements

- **Port 443**: HTTPS access to Azure (management operations)
- **Port 445**: SMB access to Azure Files (data transfer)
- **Bandwidth**: 1Gbps recommended for large migrations
- **Same VNet**: Best performance when VM is in same VNet as storage accounts

## Installation

1. **Clone or download the script:**

```powershell
git clone https://github.com/shawntmeyer/FSLogix.git
cd FSLogix\migrateStorage
```

1. **Install prerequisites:**

```powershell
# Install Hyper-V PowerShell module (requires restart)
Install-WindowsFeature -Name Hyper-V-PowerShell -IncludeManagementTools

# Install Azure PowerShell module
Install-Module -Name Az -Repository PSGallery -Force -AllowClobber

# Install AzCopy (optional - for concurrent processing)
# Download from https://aka.ms/downloadazcopy
# Extract and add to PATH, or place in script directory
```

1. **Verify installation:**

```powershell
# Test Hyper-V module
Get-Module -ListAvailable -Name Hyper-V

# Test Azure module
Get-Module -ListAvailable -Name Az

# Test AzCopy (optional)
azcopy --version
```

## Usage

### Basic Syntax

```powershell
.\Migrate-Containers.ps1 `
    -SourceStorageAccountName <string> `
    -SourceShareName <string> `
    [-DestStorageAccountName <string>] `
    [-DestShareName <string>] `
    [-OutputType <VHD|VHDX>] `
    [-RenameFolders] `
    [-UseStorageKey] `
    [-UseAzCopy] `
    [-ConcurrentJobs <int>]
```

### Example Scenarios

#### 1. Simple Migration (VHD → VHDX) - Different Storage Accounts

**Scenario**: Migrate all profiles from old storage to new storage with VHDX conversion

```powershell
# Login to Azure
Connect-AzAccount

# Run migration
.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "oldstorageaccount" `
    -SourceShareName "profiles" `
    -DestStorageAccountName "newstorageaccount" `
    -DestShareName "profiles"
```

**Expected Time**: ~2 minutes per 10GB profile (sequential)

---

#### 2. Large Migration with Concurrent Processing

**Scenario**: Migrate 100+ profiles quickly using parallel processing

```powershell
# Login to Azure and AzCopy
Connect-AzAccount
azcopy login

# Run migration with 8 concurrent jobs
.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "oldsa" `
    -SourceShareName "profiles" `
    -DestStorageAccountName "newsa" `
    -DestShareName "profiles" `
    -UseAzCopy `
    -ConcurrentJobs 8
```

**Expected Time**: ~45-60 minutes for 100x10GB profiles

---

#### 3. In-Place VHD Optimization

**Scenario**: Optimize existing VHD files to dynamic VHD format (reclaim space)

```powershell
Connect-AzAccount

.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "storageaccount" `
    -SourceShareName "profiles" `
    -OutputType VHD
```

**Note**: Original VHD is backed up as `.vhd.backup` during conversion

---

#### 4. Migration with Folder Renaming

**Scenario**: Change folder naming convention from `SID_username` to `username_SID`

```powershell
Connect-AzAccount

.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "storageaccount" `
    -SourceShareName "profiles" `
    -RenameFolders
```

**Before**: `S-1-5-21-xxx_jdoe`  
**After**: `jdoe_S-1-5-21-xxx`

---

#### 5. Using Storage Account Key Authentication

**Scenario**: Use storage keys instead of Entra ID (for testing or when RBAC not configured)

```powershell
Connect-AzAccount

.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "storageaccount" `
    -SourceShareName "profiles" `
    -UseStorageKey
```

---

#### 6. Custom Administrator Groups for ACLs

**Scenario**: Grant specific domain admin groups full control

```powershell
Connect-AzAccount

.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "storageaccount" `
    -SourceShareName "profiles" `
    -AdministratorGroupSIDs @('S-1-5-32-544', 'S-1-5-21-xxx-512')
```

---

#### 7. Cross-Region Migration

**Scenario**: Migrate profiles from one Azure region to another

```powershell
Connect-AzAccount
azcopy login

.\Migrate-Containers.ps1 `
    -SourceStorageAccountName "useast-storage" `
    -SourceShareName "profiles" `
    -DestStorageAccountName "westeurope-storage" `
    -DestShareName "profiles" `
    -UseAzCopy `
    -ConcurrentJobs 4
```

**Note**: Higher latency may increase migration time

## Parameters Reference

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `SourceStorageAccountName` | String | - | **Yes** | Source storage account name |
| `SourceShareName` | String | - | **Yes** | Source file share name |
| `DestStorageAccountName` | String | Same as source | No | Destination storage account |
| `DestShareName` | String | Same as source | No | Destination file share |
| `OutputType` | String | `VHDX` | No | Output format: `VHD` or `VHDX` |
| `RenameFolders` | Switch | `$false` | No | Rename SID_user to user_SID |
| `UseStorageKey` | Switch | `$false` | No | Use storage keys instead of Entra ID |
| `UseAzCopy` | Switch | `$false` | No | Enable AzCopy with concurrency |
| `ConcurrentJobs` | Int | `4` | No | Number of parallel jobs (AzCopy only) |
| `LogPath` | String | `.\Logs` | No | Directory for log files |
| `TempPath` | String | `$env:TEMP\FSLogixMigration` | No | Temp directory (AzCopy only) |
| `AdministratorGroupSIDs` | String[] | `@('S-1-5-32-544')` | No | Admin group SIDs for ACLs |
| `UserGroupSIDs` | String[] | `@()` | No | User group SIDs for ACLs |

## Performance Considerations

### Direct UNC Method (Default)

**Characteristics:**

- Sequential processing (one profile at a time)
- No local disk space required
- Convert-VHD streams directly from source to destination
- Simple, predictable, reliable

**Best For:**

- Small-medium migrations (<50 profiles)
- Same VNet deployments
- Limited local disk space
- Simplicity over speed

**Performance:**

- **Network**: 1Gbps = ~100MB/s sustained
- **Per Profile**: ~2 minutes for 10GB
- **100 Profiles**: ~3.4 hours

### AzCopy with Concurrency

**Characteristics:**

- Parallel processing (multiple profiles simultaneously)
- Requires local disk space for temp files
- Downloads → Converts → Uploads
- Better network and CPU utilization

**Best For:**

- Large migrations (50+ profiles)
- Cross-region migrations
- When time is critical
- Adequate local storage available

**Performance:**

- **Network**: Near line-rate utilization
- **Per Profile**: ~45-60 seconds (with 8 jobs)
- **100 Profiles**: ~45-60 minutes

**Recommended Concurrent Jobs:**

| Profile Count | Recommended Jobs | Estimated Time (100x10GB) |
| ------------- | ---------------- | ------------------------- |
| <25 | 2-4 | ~90 minutes |
| 25-100 | 4-8 | ~45-60 minutes |
| >100 | 8-12 | ~30-45 minutes |

**Note**: Higher concurrency requires more CPU, memory, and local disk space.

## Output and Logging

### Console Output

Real-time progress with color-coded messages:

- **Green**: Success operations
- **Yellow**: Warnings
- **Red**: Errors
- **White**: Information

### Log Files

Located in `LogPath` (default: `.\Logs\`):

1. **Main Log**: `FSLogixMigration_YYYYMMDD_HHMMSS.log`
   - Detailed timestamped log of all operations
   - Includes debug information
   - Used for troubleshooting

2. **Results CSV**: `MigrationResults_YYYYMMDD_HHMMSS.csv`
   - Summary of each profile migration
   - Columns: SourceFolder, DestFolder, SourceVHD, DestOutput, OriginalSize, Success, Error
   - Import into Excel for analysis

### Example Output

```
[2026-01-30 10:00:00] [INFO] FSLogix Profile Migration Script
[2026-01-30 10:00:00] [INFO] Authentication Method: Entra ID (Recommended)
[2026-01-30 10:00:00] [INFO] Source: oldsa\profiles
[2026-01-30 10:00:00] [INFO] Destination: newsa\profiles
[2026-01-30 10:00:05] [SUCCESS] Found 100 VHD files to migrate
[2026-01-30 10:00:10] [INFO] Starting migration for: S-1-5-21-xxx_jdoe
[2026-01-30 10:02:05] [SUCCESS] Conversion successful. VHDX size: 8.23 GB
[2026-01-30 10:02:08] [SUCCESS] Migration completed successfully
...
[2026-01-30 13:25:15] [INFO] Migration Summary
[2026-01-30 13:25:15] [SUCCESS] Total Profiles: 100
[2026-01-30 13:25:15] [SUCCESS] Successful: 100
[2026-01-30 13:25:15] [INFO] Failed: 0
[2026-01-30 13:25:15] [INFO] Duration: 03:25:10
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

**Symptom**: `Access is denied` when accessing storage or setting ACLs

**Solutions**:

1. Verify RBAC role assignment:

```powershell
Get-AzRoleAssignment `
    -Scope "/subscriptions/{subscription-id}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{sa}" `
    -SignInName "user@domain.com"
```

2. Ensure you're logged in: `Connect-AzAccount`

3. Try using `-UseStorageKey` as alternative

4. Verify storage account firewall allows your IP

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

#### AzCopy Not Found

**Symptom**: `AzCopy not found in PATH`

**Solution**:

1. Download from [https://aka.ms/downloadazcopy](https://aka.ms/downloadazcopy)
2. Extract to `C:\AzCopy\` (or any location)

3. Add to PATH:
```powershell
$env:Path += ";C:\AzCopy"
[Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")
```

4. Or copy `azcopy.exe` to script directory

#### Slow Performance

**Symptom**: Migration taking longer than expected

**Solutions**:

1. Use `-UseAzCopy -ConcurrentJobs 8` for parallel processing
2. Verify network bandwidth: `Test-NetConnection -ComputerName storageaccount.file.core.windows.net -Port 445`
3. Check if VM is in same VNet as storage accounts
4. Reduce `-ConcurrentJobs` if CPU/memory constrained
5. Verify storage account isn't throttled (check Azure Portal metrics)

#### Out of Disk Space

**Symptom**: Error during AzCopy conversion - insufficient disk space

**Solutions**:

1. Free up space in temp directory
2. Change temp path: `-TempPath "D:\Temp"`
3. Use direct UNC method instead (no `-UseAzCopy`)
4. Migrate in smaller batches

## Best Practices

### Before Migration

1. **Test First**: Run with 5-10 test profiles before full migration
2. **Verify Permissions**: Confirm RBAC role assignment on both storage accounts
3. **Check Network**: Ensure Port 445 is open and reachable
4. **Plan Downtime**: Schedule during maintenance window
5. **Backup**: Ensure source profiles are backed up (script doesn't delete source)
6. **Document SIDs**: If using custom admin/user groups, document SIDs used

### During Migration

1. **Monitor Progress**: Watch console output and log files
2. **Check Azure Portal**: Monitor storage account metrics
3. **Verify Network**: Ensure stable network connection
4. **Resource Monitoring**: Check CPU, memory, and disk usage on migration VM
5. **Spot Check**: Periodically verify migrated profiles are accessible

### After Migration

1. **Verify ACLs**: Spot check permissions on migrated profiles
2. **Test Access**: Have test users log in to verify profiles work
3. **Review Logs**: Check for any warnings or errors
4. **Update FSLogix**: Point FSLogix to new storage location
5. **Monitor**: Watch for user login issues
6. **Cleanup**: Remove old profiles after confirming migration success (wait 30+ days)

## FSLogix Configuration Updates

After migrating profiles, you must update FSLogix registry settings to reflect the new storage location and profile format. These settings are typically managed via Group Policy or registry.

### Required Registry Settings

FSLogix settings are located at:

- **Registry Path**: `HKLM\SOFTWARE\FSLogix\Profiles`
- **Group Policy**: Computer Configuration → Policies → Administrative Templates → FSLogix

### Settings That Must Be Updated

#### 1. VHDLocations (Critical)

**When to Update**: Always update if migrating to a different storage account or share name.

**Registry Key**: `VHDLocations`  
**Type**: `REG_MULTI_SZ` or `REG_SZ`  
**Purpose**: Specifies the path(s) where FSLogix profile containers are stored.

**Before Migration Example:**

```
\\oldstorageaccount.file.core.windows.net\profiles
```

**After Migration Example:**

```
\\newstorageaccount.file.core.windows.net\profiles
```

**PowerShell Update:**

```powershell
# Single location
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "VHDLocations" `
    -Value "\\newstorageaccount.file.core.windows.net\profiles" `
    -Type MultiString

# Multiple locations (for Cloud Cache or redundancy)
$locations = @(
    "\\newstorageaccount.file.core.windows.net\profiles",
    "type=smb,connectionString=\\backupsa.file.core.windows.net\profiles"
)
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "VHDLocations" `
    -Value $locations `
    -Type MultiString
```

**Group Policy**: FSLogix → Profile Containers → Container and Directory Naming → VHD Location(s)

---

#### 2. VolumeType (If Changed to VHDX)

**When to Update**: If you migrated from VHD to VHDX format (default behavior of this script).

**Registry Key**: `VolumeType`  
**Type**: `REG_SZ`  
**Purpose**: Specifies the container file format.

**Values:**

- `VHD` = Virtual Hard Disk format (legacy, 2TB max)
- `VHDX` = Hyper-V Virtual Hard Disk format (recommended, 64TB max)

**PowerShell Update:**

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "VolumeType" `
    -Value "VHDX" `
    -Type String
```

**Group Policy**: FSLogix → Profile Containers → Container and Directory Naming → Virtual Disk Type

**Note**: This setting affects **new** profiles only. Existing profiles remain in their current format unless migrated.

---

#### 3. VHDType (Dynamic vs Fixed)

**When to Update**: If you changed disk allocation type during migration (this script creates dynamic disks).

**Registry Key**: `IsDynamic`  
**Type**: `REG_DWORD`  
**Purpose**: Determines if new containers are dynamically expanding or fixed size.

**Values:**

- `0` = Fixed size (allocates full size immediately)
- `1` = Dynamic expansion (grows as needed, recommended)

**PowerShell Update:**

```powershell
# Set to dynamic (recommended for migrated profiles)
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "IsDynamic" `
    -Value 1 `
    -Type DWord
```

**Group Policy**: FSLogix → Profile Containers → Container and Directory Naming → Is Dynamic (VHD)

**Important**: This script converts profiles to **dynamic** format. Set this to `1` to ensure new profiles match.

---

### Optional Settings to Review

#### SizeInMBs (Profile Size Limit)

**Registry Key**: `SizeInMBs`  
**Type**: `REG_DWORD`  
**Default**: `30000` (30GB)

If migrating to VHDX (which supports larger sizes), consider increasing:

```powershell
# Increase max profile size to 100GB
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "SizeInMBs" `
    -Value 102400 `
    -Type DWord
```

#### FlipFlopProfileDirectoryName

**Registry Key**: `FlipFlopProfileDirectoryName`  
**Type**: `REG_DWORD`  
**Values**: `0` = SID_username | `1` = username_SID

If you used `-RenameFolders` parameter to change folder naming convention:

```powershell
# If migrated from SID_username to username_SID
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "FlipFlopProfileDirectoryName" `
    -Value 1 `
    -Type DWord
```

### Deploying Changes via Group Policy

**Recommended Method**: Use Group Policy for centralized management.

1. **Open Group Policy Management Console (GPMC)**

2. **Navigate to FSLogix Settings**:

   ```
   Computer Configuration → Policies → Administrative Templates → FSLogix → Profile Containers
   ```

3. **Update Required Policies**:
   - **Enabled**: Enable Profile Container
   - **VHD Location(s)**: New storage path(s)
   - **Virtual Disk Type**: VHDX
   - **Is Dynamic (VHD)**: Enabled

4. **Force GPO Update** (Optional):

   ```powershell
   gpupdate /force
   ```

### Verification Steps

After updating FSLogix settings:

1. **Verify Registry Values**:

    ```powershell
    Get-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" | Format-List
    ```

1. **Test User Login**:
   - Have a test user log in to a session host
   - Verify profile loads from new location
   - Check Event Viewer → Applications and Services Logs → FSLogix-Apps/Operational

2. **Monitor Profile Access**:

    ```powershell
    # Check if new location is accessible
    Test-Path "\\newstorageaccount.file.core.windows.net\profiles"

    # Verify specific user profile
    Test-Path "\\newstorageaccount.file.core.windows.net\profiles\username_S-1-5-21-xxx\Profile_username.vhdx"
    ```

4. **Review FSLogix Logs**:

   - Location: `C:\ProgramData\FSLogix\Logs`
   - Look for: `Profile` logs
   - Confirm: Successful profile mounting from new location

### Common Configuration Mistakes

❌ **Mistake**: Forgetting to update VHDLocations  
✅ **Result**: Users get new blank profiles instead of migrated ones

❌ **Mistake**: Setting VolumeType=VHD when profiles are VHDX  
✅ **Result**: FSLogix can still mount existing VHDX, but new profiles would be VHD

❌ **Mistake**: Not updating Cloud Cache locations  
✅ **Result**: Cloud Cache tries to sync to old location

❌ **Mistake**: Mismatched FlipFlopProfileDirectoryName setting  
✅ **Result**: FSLogix can't find existing profiles due to naming mismatch

### Cloud Cache Considerations

If using FSLogix Cloud Cache, update **both** locations:

```powershell
$ccLocations = @(
    "type=smb,connectionString=\\newprimarysa.file.core.windows.net\profiles",
    "type=smb,connectionString=\\newsecondarysa.file.core.windows.net\profiles"
)
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" `
    -Name "CCDLocations" `
    -Value $ccLocations `
    -Type MultiString
```

### Reference Links

- [FSLogix Configuration Reference](https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings)
- [FSLogix Profile Container Settings](https://learn.microsoft.com/en-us/fslogix/profile-container-configuration-reference)
- [FSLogix Group Policy Templates](https://aka.ms/fslogix/download)
- [Troubleshooting FSLogix Profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-profiles)

## Security Considerations

### Authentication

- **Entra ID**: Most secure, uses RBAC, supports MFA, audit logs
- **Storage Keys**: Less secure, shared secret, rotate regularly

### Data in Transit

- SMB 3.0 with encryption enabled by default on Azure Files
- HTTPS for management operations
- Consider VPN or Private Endpoint for additional security

### Permissions

- Script requires elevated privileges for ACL operations
- Run from secure jump box or administrative workstation
- Use Just-In-Time (JIT) access if available
- Audit who has access to run migrations

### Logging

- Logs contain profile folder names (may include usernames)
- Store logs securely
- Review access to log directories
- Consider log retention policies

## Limitations

- **Windows Only**: Requires Windows OS with Hyper-V PowerShell module
- **VHD/VHDX Only**: Only processes VHD/VHDX files (not other profile types)
- **Sequential ACL Setting**: ACLs set sequentially even with concurrent migrations
- **No Resume**: Failed profiles must be re-migrated (no checkpoint/resume)
- **Same VHDX Version**: Output VHDX version matches Convert-VHD defaults
- **No Dedupe**: Does not deduplicate data between profiles

## FAQ

**Q: Will source profiles be deleted?**  
A: No. When migrating between storage accounts, source profiles remain untouched. For in-place VHD optimization, originals are backed up as `.vhd.backup` and deleted only after successful conversion.

**Q: Can I pause and resume the migration?**  
A: No. The script processes profiles sequentially or in parallel batches. If interrupted, you can re-run the script and it will process all profiles again (including already migrated ones).

**Q: What happens if a profile fails to migrate?**  
A: The script logs the error and continues with the next profile. Check the log file and CSV results for details. Failed profiles can be re-migrated individually or in a second pass.

**Q: Can I migrate from on-premises to Azure Files?**  
A: Yes, if the on-premises file server is accessible via UNC path and you have appropriate permissions. Performance will depend on your internet connection.

**Q: Does this work with FSLogix Cloud Cache?**  
A: Yes, the script can migrate both local and cloud cache VHD/VHDX files. Ensure both primary and cloud cache locations are migrated if using redirections.

**Q: What's the difference between VHD and VHDX output?**  
A: VHDX supports larger sizes (64TB vs 2TB), better corruption resistance, and improved performance. Recommended for new deployments. VHD may be needed for legacy compatibility.

**Q: Can I run multiple instances of the script simultaneously?**  
A: Not recommended. Both instances would process the same profiles, wasting resources and potentially causing conflicts. Use `-UseAzCopy -ConcurrentJobs` instead for parallelism.

## Support

- **Issues**: [GitHub Issues](https://github.com/shawntmeyer/FSLogix/issues)
- **Documentation**: [FSLogix Docs](https://learn.microsoft.com/en-us/fslogix/)
- **Azure Files**: [Azure Files Docs](https://learn.microsoft.com/en-us/azure/storage/files/)

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

## License

This script is provided as-is under the MIT License. See LICENSE file for details.

## Changelog

### Version 1.0 (2026-01-30)

- Initial release
- VHD to VHDX conversion
- VHD to dynamic VHD optimization
- Dual authentication (Entra ID / Storage Keys)
- Direct UNC and AzCopy methods
- Concurrent processing support
- ACL management with Creator Owner
- Folder renaming (SID_username ↔ username_SID)
- Comprehensive logging and reporting

---

**Last Updated**: January 30, 2026  
**Tested On**: Windows Server 2019/2022, Windows 10/11 Pro/Enterprise  
**PowerShell Version**: 5.1, 7.x
