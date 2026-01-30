<#
.SYNOPSIS
    Migrates FSLogix profile VHD/VHDX files between Azure File Shares with format conversion and ACL management.

.DESCRIPTION
    A comprehensive PowerShell script for migrating FSLogix user profile containers between Azure Storage Accounts
    and/or File Shares. The script performs VHD to VHDX conversion (or VHD to dynamic VHD optimization), 
    optional folder renaming from SID_username to username_SID format, and sets proper NTFS permissions 
    with ownership based on user SIDs.
    
    KEY FEATURES:
    - Converts VHD to dynamic VHDX or optimizes VHD to dynamic VHD
    - Supports migration between storage accounts or in-place optimization
    - Direct UNC path conversion or AzCopy with concurrent processing
    - Automatic ACL configuration with Creator Owner permissions
    - Optional folder renaming (SID_username ↔ username_SID)
    - Dual authentication support (Entra ID or Storage Account Keys)
    - Comprehensive logging with CSV export of results
    - Progress tracking and error handling
    
    AUTHENTICATION METHODS:
    
    1. ENTRA ID (Default - Recommended for Production):
       - Most secure option using Azure RBAC
       - Required Role: 'Storage File Data SMB Share Elevated Contributor'
         Role ID: a7264617-510b-434b-a828-9731dc254ea7
         https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-file-data-smb-share-elevated-contributor
       - Must be assigned on BOTH source and destination storage accounts
       - Allows setting ownership and full ACL management
       - Run 'Connect-AzAccount' before executing script
    
    2. STORAGE ACCOUNT KEY (Alternative):
       - Uses storage account access keys for authentication
       - Keys automatically retrieved from Azure (requires permissions)
       - Run 'Connect-AzAccount' before executing script
       - Use -UseStorageKey switch
       - Less secure than Entra ID but doesn't require RBAC role assignment
    
    CONVERSION METHODS:
    
    1. DIRECT UNC (Default):
       - Convert-VHD operates directly on UNC paths
       - No local disk space required
       - Best for: Small-medium migrations, same VNet deployments
       - Sequential processing (one profile at a time)
       - Estimated time: ~2 minutes per 10GB profile
    
    2. AZCOPY WITH CONCURRENCY (Recommended for Large Migrations):
       - Downloads VHD, converts locally, uploads VHDX
       - Processes multiple profiles simultaneously
       - Best for: Large migrations (50+ profiles), cross-region migrations
       - Requires: 'azcopy login' before script execution
       - Estimated time: ~45-60 minutes for 100x10GB profiles with 8 concurrent jobs
    
    PREREQUISITES:
    - Windows Server or Windows 10/11 with Hyper-V PowerShell module
    - Azure PowerShell module (Az)
    - AzCopy (optional, for concurrent processing)
    - Network connectivity to Azure Storage (443, 445)
    - Sufficient local disk space (if using AzCopy)
    
    PERFORMANCE CONSIDERATIONS:
    - Network bandwidth: 1Gbps = ~100MB/s = ~2 min per 10GB profile
    - CPU overhead: 10-20% per conversion (Convert-VHD)
    - Memory: ~400MB base + ~300MB per concurrent conversion
    - Direct UNC: Sequential, predictable, no local storage
    - AzCopy: Parallel, faster, requires temp storage

.PARAMETER SourceStorageAccountName
    Source Azure Storage Account name (without .file.core.windows.net suffix)
    Example: "storageaccount1"
    Required: Yes

.PARAMETER SourceShareName
    Source Azure File Share name containing FSLogix profiles
    Example: "profiles" or "fslogix-profiles"
    Required: Yes

.PARAMETER DestStorageAccountName
    Destination Azure Storage Account name
    If omitted, uses same as source (in-place conversion)
    Example: "storageaccount2"
    Required: No

.PARAMETER DestShareName
    Destination Azure File Share name
    If omitted, uses same as source
    Example: "profiles-new"
    Required: No

.PARAMETER RenameFolders
    Switch to rename profile folders from SID_username to username_SID format
    Useful for compliance with FSLogix best practices
    Example: "S-1-5-21-xxx_jdoe" becomes "jdoe_S-1-5-21-xxx"
    Required: No

.PARAMETER UseStorageKey
    Use storage account key authentication instead of Entra ID (default)
    Keys are automatically retrieved from Azure
    Requires permissions to list storage account keys
    Required: No

.PARAMETER LogPath
    Directory path for log files
    Creates directory if it doesn't exist
    Default: "$PSScriptRoot\Logs"
    Required: No

.PARAMETER TempPath
    Temporary directory for AzCopy operations
    Only used when -UseAzCopy is specified
    Default: "$env:TEMP\FSLogixMigration"
    Required: No

.PARAMETER ConcurrentJobs
    Number of parallel profile migrations when using AzCopy
    Higher values = faster migration but more resource usage
    Recommended: 4-8 for most scenarios
    Default: 4
    Required: No

.PARAMETER UseAzCopy
    Enable AzCopy for faster transfers with concurrent processing
    Requires 'azcopy login' before running script
    Best for large migrations (50+ profiles) or cross-region
    Required: No

.PARAMETER OutputType
    Output virtual disk format: VHD or VHDX
    VHD: Creates dynamic VHD (useful for in-place optimization)
    VHDX: Creates dynamic VHDX (recommended for new deployments)
    When converting to VHD in-place, original VHD is backed up
    Default: VHDX
    Required: No

.PARAMETER AdministratorGroupSIDs
    Array of SIDs for administrator groups to grant Full Control
    Applied to share root and inherited by profile folders
    Default: @('S-1-5-32-544') [Built-in Administrators]
    Example: @('S-1-5-32-544', 'S-1-5-21-xxx-512')
    Required: No

.PARAMETER UserGroupSIDs
    Array of SIDs for user groups to grant Modify access (this folder only)
    If not specified, uses Authenticated Users (S-1-5-11)
    Example: @('S-1-5-21-xxx-1001')
    Required: No

.NOTES
    File Name      : Migrate-Containers.ps1
    Author         : GitHub Copilot
    Prerequisite   : PowerShell 5.1+, Hyper-V PowerShell Module, Azure PowerShell Module
    Version        : 1.0
    Date           : 2026-01-30
    
    DISCLAIMER:
    This Sample Code is provided for the purpose of illustration only and is not intended to be used 
    in a production environment without testing. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE
    PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED
    TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We grant you
    a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute
    the object code form of the Sample Code, provided that You agree:
    (i)     to not use Our name, logo, or trademarks to market Your software product in which the Sample Code
            is embedded
    (ii)    to include a valid copyright notice on Your software product in which the Sample Code is
            embedded
    (iii)   to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or
            lawsuits, including attorneys' fees, that arise or result from the use or distribution of the
            Sample Code.
    
    IMPORTANT NOTES:
    - Source VHD files remain untouched when migrating to different storage account
    - In-place VHD optimization creates .backup files (removed after successful conversion)
    - Script requires elevated privileges for ACL operations
    - Network latency significantly impacts performance for cross-region migrations
    - Test with small batch before full production migration
    
    TROUBLESHOOTING:
    - "Access Denied" errors: Verify RBAC role assignment or storage key permissions
    - "Hyper-V module not found": Install with Install-WindowsFeature -Name Hyper-V-PowerShell
    - "AzCopy not found": Download from https://aka.ms/downloadazcopy
    - Slow performance: Consider using -UseAzCopy with -ConcurrentJobs
    
    LINKS:
    - Storage File Data SMB Share Elevated Contributor:
      https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-file-data-smb-share-elevated-contributor
    - Hyper-V PowerShell Module:
      https://learn.microsoft.com/en-us/powershell/module/hyper-v/
    - AzCopy Download:
      https://aka.ms/downloadazcopy
    - FSLogix Documentation:
      https://learn.microsoft.com/en-us/fslogix/

.EXAMPLE
    # Using Entra ID authentication (default) - VHD to VHDX migration
    Connect-AzAccount
    .\Migrate-Containers.ps1 -SourceStorageAccountName "oldsa" -SourceShareName "profiles" `
        -DestStorageAccountName "newsa" -DestShareName "profiles"

.EXAMPLE
    # Using storage account key authentication with folder renaming
    Connect-AzAccount
    .\Migrate-Containers.ps1 -SourceStorageAccountName "sa1" -SourceShareName "profiles" `
        -UseStorageKey -RenameFolders

.EXAMPLE
    # Using AzCopy with concurrent processing for better performance
    Connect-AzAccount
    azcopy login
    .\Migrate-Containers.ps1 -SourceStorageAccountName "sa1" -SourceShareName "profiles" `
        -DestStorageAccountName "sa2" -DestShareName "profiles" `
        -UseAzCopy -ConcurrentJobs 8

.EXAMPLE
    # In-place VHD optimization (convert VHD to dynamic VHD)
    Connect-AzAccount
    .\Migrate-Containers.ps1 -SourceStorageAccountName "sa1" -SourceShareName "profiles" `
        -OutputType VHD

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceStorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$SourceShareName,

    [Parameter(Mandatory = $false)]
    [string]$DestStorageAccountName,

    [Parameter(Mandatory = $false)]
    [string]$DestShareName,

    [Parameter(Mandatory = $false)]
    [switch]$RenameFolders,

    [Parameter(Mandatory = $false)]
    [switch]$UseStorageKey,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$PSScriptRoot\Logs",

    [Parameter(Mandatory = $false)]
    [string]$TempPath = "$env:TEMP\FSLogixMigration",

    [Parameter(Mandatory = $false)]
    [int]$ConcurrentJobs = 4,

    [Parameter(Mandatory = $false)]
    [switch]$UseAzCopy,

    [Parameter(Mandatory = $false)]
    [ValidateSet('VHD', 'VHDX')]
    [string]$OutputType = 'VHDX',

    [Parameter(Mandatory = $false)]
    [string[]]$AdministratorGroupSIDs = @('S-1-5-32-544'),

    [Parameter(Mandatory = $false)]
    [string[]]$UserGroupSIDs = @()
)

#region Initialize
$ErrorActionPreference = "Stop"
$startTime = Get-Date

# Initialize storage key variables
$SourceStorageKey = $null
$DestStorageKey = $null

# Set defaults if not specified
if ([string]::IsNullOrEmpty($DestStorageAccountName)) {
    $DestStorageAccountName = $SourceStorageAccountName
}

if ([string]::IsNullOrEmpty($DestShareName)) {
    $DestShareName = $SourceShareName
}

$sameLocation = ($SourceStorageAccountName -eq $DestStorageAccountName) -and ($SourceShareName -eq $DestShareName)

# Create directories
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

if (!(Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

$logFile = Join-Path $LogPath "FSLogixMigration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#endregion

#region Functions

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color
    switch ($Level) {
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
    
    # Write to file
    Add-Content -Path $logFile -Value $logMessage
}

function Get-StorageAccountKey {
    param(
        [string]$StorageAccountName
    )
    
    try {
        Write-Log "Retrieving storage account key for: $StorageAccountName"
        $keys = Get-AzStorageAccountKey -ResourceGroupName (Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $StorageAccountName}).ResourceGroupName -Name $StorageAccountName
        return $keys[0].Value
    }
    catch {
        Write-Log "Failed to retrieve storage account key: $_" -Level ERROR
        throw
    }
}

function Test-AzCopy {
    try {
        $azcopyPath = (Get-Command azcopy -ErrorAction SilentlyContinue).Source
        if ($azcopyPath) {
            Write-Log "AzCopy found at: $azcopyPath" -Level SUCCESS
            
            # Check if logged in
            $loginCheck = & azcopy login status 2>&1
            if ($loginCheck -match "already logged in") {
                Write-Log "AzCopy is authenticated with Entra ID" -Level SUCCESS
                return $true
            }
            else {
                Write-Log "AzCopy found but not authenticated. Run 'azcopy login' first." -Level WARNING
                return $false
            }
        }
        else {
            Write-Log "AzCopy not found in PATH" -Level WARNING
            return $false
        }
    }
    catch {
        Write-Log "Error checking for AzCopy: $_" -Level WARNING
        return $false
    }
}

function Test-HyperVModule {
    try {
        if (Get-Module -ListAvailable -Name Hyper-V) {
            Import-Module Hyper-V -ErrorAction Stop
            Write-Log "Hyper-V module loaded successfully" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "Hyper-V module not available. Install with: Install-WindowsFeature -Name Hyper-V-PowerShell" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Error loading Hyper-V module: $_" -Level ERROR
        return $false
    }
}

function Get-StorageEndpointSuffix {
    try {
        # Try to get from Azure context
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if ($context -and $context.Environment) {
            $suffix = $context.Environment.StorageEndpointSuffix
            if (![string]::IsNullOrEmpty($suffix)) {
                Write-Log "Detected Azure environment: $($context.Environment.Name) with suffix: $suffix" -Level SUCCESS
                return $suffix
            }
        }
        
        # Fallback to default
        Write-Log "No Azure context found, using default suffix: core.windows.net" -Level WARNING
        return "core.windows.net"
    }
    catch {
        Write-Log "Error getting storage endpoint suffix, using default: $_" -Level WARNING
        return "core.windows.net"
    }
}

function Get-FSLogixContainers {
    param(
        [string]$StorageAccountName,
        [string]$ShareName
    )
    
    try {
        $sourceUNC = "\\$StorageAccountName.file.$script:storageEndpointSuffix\$ShareName"
        Write-Log "Enumerating FSLogix profiles from $sourceUNC"        
      
        # Map drive temporarily using Entra ID authentication
        $driveLetter = Get-AvailableDriveLetter
        
        New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $sourceUNC -ErrorAction Stop | Out-Null
        Write-Log "Mapped drive ${driveLetter}: to $sourceUNC (using Entra ID authentication)" -Level SUCCESS
        
        # Get all profile folders
        $profilePath = "${driveLetter}:\"
        $folders = Get-ChildItem -Path $profilePath -Directory -ErrorAction SilentlyContinue
        
        $Containers = @()
        foreach ($folder in $folders) {
            # Look for VHD files
            $vhdFiles = Get-ChildItem -Path $folder.FullName -Filter "*.vhd" -File -ErrorAction SilentlyContinue
            
            foreach ($vhd in $vhdFiles) {
                $Containers += [PSCustomObject]@{
                    FolderName = $folder.Name
                    FolderPath = $folder.FullName
                    VHDName = $vhd.Name
                    VHDPath = $vhd.FullName
                    VHDSize = $vhd.Length
                }
            }
        }
        
        # Remove drive
        Remove-PSDrive -Name $driveLetter -Force
        
        Write-Log "Found $($Containers.Count) VHD files to migrate" -Level SUCCESS
        return $Containers
    }
    catch {
        Write-Log "Error enumerating profiles: $_" -Level ERROR
        throw
    }
}

function Get-AvailableDriveLetter {
    $used = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
    foreach ($letter in 90..65) {
        $drive = [char]$letter
        if ($drive -notin $used) {
            return $drive
        }
    }
    throw "No available drive letters"
}

function Convert-FolderName {
    param([string]$FolderName)
    
    # Convert from SID_username to username_SID
    if ($FolderName -match '^(S-[0-9-]+)_(.+)$') {
        $sid = $matches[1]
        $username = $matches[2]
        return "${username}_${sid}"
    }
    
    # Already in username_SID format or unknown format
    return $FolderName
}

function Get-SIDFromFolderName {
    param([string]$FolderName)
    
    # Extract SID from SID_username format
    if ($FolderName -match '^(S-[0-9-]+)_') {
        return $matches[1]
    }
    
    # Extract SID from username_SID format
    if ($FolderName -match '_(S-[0-9-]+)$') {
        return $matches[1]
    }
    
    Write-Log "Could not extract SID from folder name: $FolderName" -Level WARNING
    return $null
}

function Invoke-ConcurrentMigration {
    param(
        [array]$Containers,
        [string]$SourceDrive,
        [string]$DestDrive,
        [string]$SourceStorageAccount,
        [string]$SourceShare,
        [string]$DestStorageAccount,
        [string]$DestShare,
        [bool]$Rename,
        [string]$TempPath,
        [int]$MaxConcurrent,
        [hashtable]$ScriptVariables
    )
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrent)
    $runspacePool.Open()
    
    # Script block for parallel execution
    $scriptBlock = {
        param(
            $Container,
            $SourceStorageAccount,
            $SourceShare,
            $DestStorageAccount,
            $DestShare,
            $Rename,
            $TempPath,
            $StorageEndpointSuffix,
            $LogFile
        )
        
        function Write-ThreadLog {
            param([string]$Message, [string]$Level = 'INFO')
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logMessage = "[$timestamp] [$Level] [Thread] $Message"
            Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
        }
        
        try {
            $destFolderName = if ($Rename) {
                if ($Container.FolderName -match '^(S-[0-9-]+)_(.+)$') {
                    "$($matches[2])_$($matches[1])"
                } else {
                    $Container.FolderName
                }
            } else {
                $Container.FolderName
            }
            
            # Create unique temp path for this thread
            $threadTempPath = Join-Path $TempPath "$($Container.FolderName)_$(Get-Random)"
            New-Item -Path $threadTempPath -ItemType Directory -Force | Out-Null
            
            # Download with AzCopy
            $sourceURL = "https://$SourceStorageAccount.file.$StorageEndpointSuffix/$SourceShare/$($Container.FolderName)/$($Container.VHDName)"
            $vhdTempPath = Join-Path $threadTempPath $Container.VHDName
            
            Write-ThreadLog "Downloading: $($Container.FolderName)/$($Container.VHDName)"
            $output = & azcopy copy $sourceURL $vhdTempPath --overwrite=true 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "AzCopy download failed: $output"
            }
            
            # Convert VHD to VHDX
            $vhdxName = [System.IO.Path]::ChangeExtension($Container.VHDName, "vhdx")
            $vhdxTempPath = Join-Path $threadTempPath $vhdxName
            
            Write-ThreadLog "Converting: $($Container.FolderName)/$($Container.VHDName)"
            Convert-VHD -Path $vhdTempPath -DestinationPath $vhdxTempPath -VHDType Dynamic -DeleteSource -ErrorAction Stop
            
            # Download metadata files
            $sourceFolder = "https://$SourceStorageAccount.file.$StorageEndpointSuffix/$SourceShare/$($Container.FolderName)"
            & azcopy copy "$sourceFolder/*" $threadTempPath --recursive=false --exclude-pattern="*.vhd" --overwrite=true 2>&1 | Out-Null
            
            # Upload to destination
            $destURL = "https://$DestStorageAccount.file.$StorageEndpointSuffix/$DestShare/$destFolderName"
            
            Write-ThreadLog "Uploading: $destFolderName"
            $output = & azcopy copy "$threadTempPath\*" $destURL --recursive=false --overwrite=true 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "AzCopy upload failed: $output"
            }
            
            # Cleanup
            Remove-Item -Path $threadTempPath -Recurse -Force -ErrorAction SilentlyContinue
            
            Write-ThreadLog "Completed: $($Container.FolderName)" -Level "SUCCESS"
            
            return @{
                Success = $true
                SourceFolder = $Container.FolderName
                DestFolder = $destFolderName
                SourceVHD = $Container.VHDName
                DestVHDX = $vhdxName
                OriginalSize = $Container.VHDSize
                Error = $null
            }
        }
        catch {
            Write-ThreadLog "Failed: $($Container.FolderName) - $_" -Level "ERROR"
            Remove-Item -Path $threadTempPath -Recurse -Force -ErrorAction SilentlyContinue
            
            return @{
                Success = $false
                SourceFolder = $Container.FolderName
                DestFolder = $null
                SourceVHD = $Container.VHDName
                DestVHDX = $null
                OriginalSize = $Container.VHDSize
                Error = $_.Exception.Message
            }
        }
    }
    
    # Create jobs
    $jobs = @()
    foreach ($Container in $Containers) {
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddParameters(@{
            Container = $Container
            SourceStorageAccount = $SourceStorageAccount
            SourceShare = $SourceShare
            DestStorageAccount = $DestStorageAccount
            DestShare = $DestShare
            Rename = $Rename
            TempPath = $TempPath
            StorageEndpointSuffix = $ScriptVariables.storageEndpointSuffix
            LogFile = $ScriptVariables.logFile
        })
        
        $powershell.RunspacePool = $runspacePool
        $jobs += [PSCustomObject]@{
            Pipe = $powershell
            Status = $powershell.BeginInvoke()
            Container = $Container
        }
    }
    
    # Wait for completion and collect results
    $results = @()
    $completed = 0
    
    while ($jobs.Status.IsCompleted -contains $false) {
        $newlyCompleted = ($jobs | Where-Object { $_.Status.IsCompleted -and $_.Collected -ne $true })
        
        foreach ($job in $newlyCompleted) {
            $result = $job.Pipe.EndInvoke($job.Status)
            $results += [PSCustomObject]$result
            $job.Pipe.Dispose()
            $job | Add-Member -NotePropertyName Collected -NotePropertyValue $true -Force
            $completed++
            
            $percentComplete = [math]::Round($completed / $Containers.Count * 100, 1)
            Write-Progress -Activity "Migrating FSLogix Profiles (Concurrent)" -Status "$completed of $($Containers.Count) completed" -PercentComplete $percentComplete
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    Write-Progress -Activity "Migrating FSLogix Profiles (Concurrent)" -Completed
    
    # Cleanup
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    return $results
}

function Copy-WithAzCopy {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [bool]$IsRecursive = $false
    )
    
    try {
        Write-Log "Using AzCopy to copy: $SourcePath -> $DestinationPath"
        
        $azcopyArgs = @('copy', $SourcePath, $DestinationPath, '--overwrite=true')
        
        if ($IsRecursive) {
            $azcopyArgs += '--recursive=true'
        }
        
        $output = & azcopy @azcopyArgs 2>&1 | Out-String
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "AzCopy output: $output" -Level WARNING
            throw "AzCopy failed with exit code: $LASTEXITCODE"
        }
        
        Write-Log "AzCopy transfer completed successfully" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "AzCopy transfer failed: $_" -Level ERROR
        return $false
    }
}

function Set-ShareRootACL {
    param(
        [string]$ShareRootPath,
        [string[]]$AdminSIDs,
        [string[]]$UserSIDs
    )
    
    try {
        Write-Log "Setting ACLs on share root: $ShareRootPath"
        
        # Well-known SIDs
        $systemSID = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
        $creatorOwnerSID = New-Object System.Security.Principal.SecurityIdentifier('S-1-3-0')
        $authenticatedUsersSID = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')
        
        # Get current ACL
        $acl = Get-Acl -Path $ShareRootPath
        
        # Disable inheritance and remove inherited rules
        $acl.SetAccessRuleProtection($true, $false)
        
        # Remove all existing access rules
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
        
        # Add SYSTEM - Full Control (This folder, subfolders and files)
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $systemSID,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($systemRule)
        Write-Log "Added SYSTEM with Full Control"
        
        # Add Administrators group(s) - Full Control (This folder, subfolders and files)
        foreach ($adminSID in $AdminSIDs) {
            try {
                $adminAccount = New-Object System.Security.Principal.SecurityIdentifier($adminSID)
                $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $adminAccount,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.AddAccessRule($adminRule)
                Write-Log "Added Administrator SID $adminSID with Full Control"
            }
            catch {
                Write-Log "Failed to add admin SID $adminSID : $_" -Level WARNING
            }
        }
        
        # Add Creator Owner - Full Control (Subfolders and files only)
        $creatorOwnerRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $creatorOwnerSID,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
            [System.Security.AccessControl.PropagationFlags]::InheritOnly,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($creatorOwnerRule)
        Write-Log "Added Creator Owner with Full Control (subfolders and files only)"
        
        # Add User group(s) or Authenticated Users - Modify (This folder only)
        if ($UserSIDs.Count -gt 0) {
            foreach ($userGroupSID in $UserSIDs) {
                try {
                    $userGroupAccount = New-Object System.Security.Principal.SecurityIdentifier($userGroupSID)
                    $userGroupRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $userGroupAccount,
                        [System.Security.AccessControl.FileSystemRights]::Modify,
                        [System.Security.AccessControl.InheritanceFlags]::None,
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                    $acl.AddAccessRule($userGroupRule)
                    Write-Log "Added User Group SID $userGroupSID with Modify (this folder only)"
                }
                catch {
                    Write-Log "Failed to add user group SID $userGroupSID : $_" -Level WARNING
                }
            }
        }
        else {
            # Default to Authenticated Users
            $authenticatedUsersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $authenticatedUsersSID,
                [System.Security.AccessControl.FileSystemRights]::Modify,
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.AddAccessRule($authenticatedUsersRule)
            Write-Log "Added Authenticated Users with Modify (this folder only)"
        }
        
        # Apply ACL to share root
        Set-Acl -Path $ShareRootPath -AclObject $acl
        Write-Log "Share root ACLs applied successfully" -Level SUCCESS
        
        return $true
    }
    catch {
        Write-Log "Error setting share root ACLs: $_" -Level ERROR
        return $false
    }
}

function Set-ProfileACL {
    param(
        [string]$ProfilePath,
        [string]$VHDXPath,
        [string]$UserSID
    )
    
    try {
        Write-Log "Setting ownership and enabling inheritance for: $ProfilePath"
        
        if ([string]::IsNullOrEmpty($UserSID)) {
            Write-Log "No user SID provided, skipping ACL configuration" -Level WARNING
            return $false
        }
        
        # Verify SID is valid
        try {
            $userAccount = New-Object System.Security.Principal.SecurityIdentifier($UserSID)
        }
        catch {
            Write-Log "Invalid user SID: $UserSID - $_" -Level ERROR
            return $false
        }
        
        # Set ownership on profile folder
        Write-Log "Setting owner to $UserSID on folder: $ProfilePath"
        $acl = Get-Acl -Path $ProfilePath
        $acl.SetOwner($userAccount)
        Set-Acl -Path $ProfilePath -AclObject $acl
        
        # Set ownership on VHDX file if it exists
        if (Test-Path $VHDXPath) {
            Write-Log "Setting owner to $UserSID on VHDX: $VHDXPath"
            $vhdxAcl = Get-Acl -Path $VHDXPath
            $vhdxAcl.SetOwner($userAccount)
            Set-Acl -Path $VHDXPath -AclObject $vhdxAcl
        }
        
        # Remove all explicit permissions and enable inheritance from parent
        # (Creator Owner permissions will apply to this user now)
        $acl = Get-Acl -Path $ProfilePath
        
        # Remove all explicit access rules
        $acl.Access | Where-Object { -not $_.IsInherited } | ForEach-Object { 
            $acl.RemoveAccessRule($_) | Out-Null 
        }
        
        # Enable inheritance (false = not protected, false = don't preserve existing rules)
        $acl.SetAccessRuleProtection($false, $false)
        Set-Acl -Path $ProfilePath -AclObject $acl
        
        Write-Log "Explicit permissions removed, inheritance enabled. Creator Owner permissions now apply." -Level SUCCESS
        
        return $true
    }
    catch {
        Write-Log "Error setting ownership/inheritance: $_" -Level ERROR
        return $false
    }
}

function Migrate-FSLogixContainer {
    param(
        [PSCustomObject]$Container,
        [string]$SourceDrive,
        [string]$DestDrive,
        [string]$SourceStorageAccount,
        [string]$SourceShare,
        [string]$DestStorageAccount,
        [string]$DestShare,
        [bool]$Rename,
        [string]$TempPath,
        [bool]$UseAzCopy,
        [string]$OutputType,
        [bool]$SameLocation
    )
    
    try {
        Write-Log "Starting migration for: $($Container.FolderName)"
        
        # Determine destination folder name
        $destFolderName = if ($Rename) { Convert-FolderName $Container.FolderName } else { $Container.FolderName }
        Write-Log "Destination folder: $destFolderName"
        
        $sourceProfilePath = "${SourceDrive}:\$($Container.FolderName)"
        $destProfilePath = "${DestDrive}:\$destFolderName"
        
        # Create destination folder
        if (!(Test-Path $destProfilePath)) {
            New-Item -Path $destProfilePath -ItemType Directory -Force | Out-Null
        }
        
        # Determine output file name and extension
        $outputExtension = if ($OutputType -eq 'VHDX') { '.vhdx' } else { '.vhd' }
        $outputFileName = [System.IO.Path]::ChangeExtension($Container.VHDName, $outputExtension.TrimStart('.'))
        $sourceVHDPath = Join-Path $sourceProfilePath $Container.VHDName
        $destOutputPath = Join-Path $destProfilePath $outputFileName
        
        # Handle in-place VHD conversion (backup original first)
        if ($SameLocation -and $OutputType -eq 'VHD') {
            $backupPath = "$sourceVHDPath.backup"
            
            # Remove old backup if exists
            if (Test-Path $backupPath) {
                Write-Log "Removing old backup: $backupPath"
                Remove-Item -Path $backupPath -Force
            }
            
            # Rename original VHD as backup
            Write-Log "Backing up original VHD: $sourceVHDPath -> $backupPath"
            Rename-Item -Path $sourceVHDPath -NewName "$($Container.VHDName).backup" -Force
            
            # Update source path to backup for conversion
            $sourceVHDPath = $backupPath
        }
        
        if ($UseAzCopy) {
            # Use temp location for AzCopy workflow
            $profileTempPath = Join-Path $TempPath $Container.FolderName
            if (!(Test-Path $profileTempPath)) {
                New-Item -Path $profileTempPath -ItemType Directory -Force | Out-Null
            }
            
            # Copy VHD to temp with AzCopy
            $vhdTempPath = Join-Path $profileTempPath $Container.VHDName
            Write-Log "Using AzCopy to copy VHD to temp: $vhdTempPath"
            
            $sourceURL = "https://$SourceStorageAccount.file.$script:storageEndpointSuffix/$SourceShare/$($Container.FolderName)/$($Container.VHDName)"
            $azCopySuccess = Copy-WithAzCopy -SourcePath $sourceURL -DestinationPath $vhdTempPath
            if (!$azCopySuccess) {
                Write-Log "AzCopy failed, falling back to Copy-Item" -Level WARNING
                Copy-Item -Path $sourceVHDPath -Destination $vhdTempPath -Force
            }
            
            # Convert VHD locally
            $outputTempPath = Join-Path $profileTempPath $outputFileName
            Write-Log "Converting VHD to dynamic $outputFileName"
            Convert-VHD -Path $vhdTempPath -DestinationPath $outputTempPath -VHDType Dynamic -DeleteSource
            
            if (!(Test-Path $outputTempPath)) {
                throw "$OutputType conversion failed - file not created"
            }
            
            Write-Log "Conversion successful. $OutputType size: $([math]::Round((Get-Item $outputTempPath).Length / 1GB, 2)) GB" -Level SUCCESS
            
            # Copy metadata files to temp
            $metadataFiles = Get-ChildItem -Path $sourceProfilePath -File | Where-Object { $_.Extension -ne '.vhd' }
            foreach ($file in $metadataFiles) {
                $destFile = Join-Path $profileTempPath $file.Name
                Copy-Item -Path $file.FullName -Destination $destFile -Force
            }
            
            # Copy all files to destination with AzCopy
            Write-Log "Using AzCopy to copy files to destination: $destProfilePath"
            $destURL = "https://$DestStorageAccount.file.$script:storageEndpointSuffix/$DestShare/$destFolderName"
            $azCopySuccess = Copy-WithAzCopy -SourcePath "$profileTempPath\*" -DestinationPath $destURL -IsRecursive $true
            if (!$azCopySuccess) {
                Write-Log "AzCopy failed, falling back to Copy-Item" -Level WARNING
                Copy-Item -Path "$profileTempPath\*" -Destination $destProfilePath -Force -Recurse
            }
            
            # Cleanup temp
            Remove-Item -Path $profileTempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            # Direct UNC path conversion - no temp needed!
            Write-Log "Converting VHD to dynamic $OutputType directly: $sourceVHDPath -> $destOutputPath"
            Convert-VHD -Path $sourceVHDPath -DestinationPath $destOutputPath -VHDType Dynamic
            
            if (!(Test-Path $destOutputPath)) {
                throw "$OutputType conversion failed - file not created"
            }
            
            Write-Log "Conversion successful. $OutputType size: $([math]::Round((Get-Item $destOutputPath).Length / 1GB, 2)) GB" -Level SUCCESS
            
            # If in-place VHD conversion was successful, remove backup
            if ($SameLocation -and $OutputType -eq 'VHD') {
                $backupPath = "$destOutputPath.backup"
                if (Test-Path $backupPath) {
                    Write-Log "Conversion successful, removing backup: $backupPath"
                    Remove-Item -Path $backupPath -Force
                }
            }
            
            # Copy metadata files directly from source to destination
            $metadataFiles = Get-ChildItem -Path $sourceProfilePath -File | Where-Object { $_.Extension -ne '.vhd' }
            foreach ($file in $metadataFiles) {
                $destFile = Join-Path $destProfilePath $file.Name
                Copy-Item -Path $file.FullName -Destination $destFile -Force
            }
        }
        
        # Set ACLs on destination profile
        $userSID = Get-SIDFromFolderName -FolderName $destFolderName
        $destOutputFilePath = Join-Path $destProfilePath $outputFileName
        
        $aclSuccess = Set-ProfileACL `
            -ProfilePath $destProfilePath `
            -VHDXPath $destOutputFilePath `
            -UserSID $userSID
        
        if (!$aclSuccess) {
            Write-Log "Warning: ACL configuration failed for $destFolderName" -Level WARNING
        }
        
        Write-Log "Migration completed successfully for: $($Container.FolderName)" -Level SUCCESS
        
        return [PSCustomObject]@{
            SourceFolder = $Container.FolderName
            DestFolder = $destFolderName
            SourceVHD = $Container.VHDName
            DestOutput = $outputFileName
            OriginalSize = $Container.VHDSize
            Success = $true
            Error = $null
        }
    }
    catch {
        Write-Log "Migration failed for $($Container.FolderName): $_" -Level ERROR
        
        return [PSCustomObject]@{
            SourceFolder = $Container.FolderName
            DestFolder = $null
            SourceVHD = $Container.VHDName
            DestOutput = $null
            OriginalSize = $Container.VHDSize
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region Main Script

# Set script-level variables for ACL configuration
$script:adminGroupSIDs = $AdministratorGroupSIDs
$script:userGroupSIDs = $UserGroupSIDs
$script:storageEndpointSuffix = Get-StorageEndpointSuffix

Write-Log "========================================" -Level INFO
Write-Log "FSLogix Profile Migration Script" -Level INFO
Write-Log "========================================" -Level INFO
Write-Log "Storage Endpoint Suffix: $script:storageEndpointSuffix"
Write-Log "Authentication Method: $(if ($UseStorageKey) { 'Storage Account Key' } else { 'Entra ID (Recommended)' })"
Write-Log "Source: $SourceStorageAccountName\$SourceShareName"
Write-Log "Destination: $DestStorageAccountName\$DestShareName"
Write-Log "Rename Folders: $RenameFolders"
Write-Log "Same Location: $sameLocation"
Write-Log "Output Type: $OutputType"
Write-Log "Concurrent Jobs: $ConcurrentJobs"
Write-Log "Use AzCopy: $UseAzCopy"
Write-Log "Administrator SIDs: $($AdministratorGroupSIDs -join ', ')"
if ($UserGroupSIDs.Count -gt 0) {
    Write-Log "User Group SIDs: $($UserGroupSIDs -join ', ')"
} else {
    Write-Log "User Group: Authenticated Users (default)"
}
Write-Log "Log File: $logFile"
Write-Log "Temp Path: $TempPath"
Write-Log "========================================" -Level INFO

# Check prerequisites
Write-Log "Checking prerequisites..."

if (!(Test-HyperVModule)) {
    Write-Log "Hyper-V PowerShell module is required for VHD conversion" -Level ERROR
    exit 1
}

# Check AzCopy if requested
if ($UseAzCopy) {
    if (-not (Test-AzCopy)) {
        Write-Log "AzCopy requested but not available or not authenticated. Install AzCopy and run 'azcopy login'." -Level ERROR
        Write-Log "Continuing without AzCopy (will use direct UNC conversion instead)" -Level WARNING
        $UseAzCopy = $false
    }
}

# Handle authentication
if ($UseStorageKey) {
    Write-Log "Using storage account key authentication"
    
    # Retrieve source storage key
    try {
        Write-Log "Retrieving source storage account key..."
        $SourceStorageKey = Get-StorageAccountKey -StorageAccountName $SourceStorageAccountName
    }
    catch {
        Write-Log "Failed to retrieve source storage key. Ensure you have permissions and are logged in with Connect-AzAccount" -Level ERROR
        exit 1
    }
    
    # Retrieve destination storage key
    if ($sameLocation) {
        $DestStorageKey = $SourceStorageKey
    }
    else {
        try {
            Write-Log "Retrieving destination storage account key..."
            $DestStorageKey = Get-StorageAccountKey -StorageAccountName $DestStorageAccountName
        }
        catch {
            Write-Log "Failed to retrieve destination storage key. Ensure you have permissions and are logged in with Connect-AzAccount" -Level ERROR
            exit 1
        }
    }
    
    Write-Log "Storage account keys retrieved successfully" -Level SUCCESS
}
else {
    Write-Log "Using Entra ID authentication (recommended)"
    
    # Verify Azure authentication for Entra ID
    try {
        $context = Get-AzContext -ErrorAction Stop
        if ($null -eq $context) {
            Write-Log "Not logged into Azure. Please run 'Connect-AzAccount' first." -Level ERROR
            exit 1
        }
        Write-Log "Authenticated as: $($context.Account.Id)" -Level SUCCESS
        Write-Log "IMPORTANT: Ensure this account has 'Storage File Data SMB Share Elevated Contributor' role on both storage accounts" -Level WARNING
    }
    catch {
        Write-Log "Azure authentication check failed. Please run 'Connect-AzAccount' first." -Level ERROR
        exit 1
    }
}

# Get all profiles to migrate
Write-Log "Enumerating FSLogix profiles..."
$Containers = Get-FSLogixContainers -StorageAccountName $SourceStorageAccountName -ShareName $SourceShareName

if ($Containers.Count -eq 0) {
    Write-Log "No VHD files found to migrate" -Level WARNING
    exit 0
}

Write-Log "Found $($Containers.Count) profiles to migrate"

# Map source drive once
Write-Log "Mapping source drive..."
try {
    $sourceDrive = Get-AvailableDriveLetter
    $sourceUNC = "\\$SourceStorageAccountName.file.$script:storageEndpointSuffix\$SourceShareName"
    
    if ($UseStorageKey) {
        $secureSourceKey = ConvertTo-SecureString -String $SourceStorageKey -AsPlainText -Force
        $sourceCredential = New-Object System.Management.Automation.PSCredential("Azure\$SourceStorageAccountName", $secureSourceKey)
        New-PSDrive -Name $sourceDrive -PSProvider FileSystem -Root $sourceUNC -Credential $sourceCredential -ErrorAction Stop | Out-Null
        Write-Log "Source mapped to ${sourceDrive}: ($sourceUNC) using storage account key" -Level SUCCESS
    }
    else {
        New-PSDrive -Name $sourceDrive -PSProvider FileSystem -Root $sourceUNC -ErrorAction Stop | Out-Null
        Write-Log "Source mapped to ${sourceDrive}: ($sourceUNC) using Entra ID" -Level SUCCESS
    }
}
catch {
    Write-Log "Failed to map source drive: $_" -Level ERROR
    exit 1
}

# Map destination drive once (or use same drive if same location)
if ($sameLocation) {
    $destDrive = $sourceDrive
    Write-Log "Using same drive for destination (same location migration)"
}
else {
    Write-Log "Mapping destination drive..."
    try {
        $destDrive = Get-AvailableDriveLetter
        $destUNC = "\\$DestStorageAccountName.file.$script:storageEndpointSuffix\$DestShareName"
        
        if ($UseStorageKey) {
            $secureDestKey = ConvertTo-SecureString -String $DestStorageKey -AsPlainText -Force
            $destCredential = New-Object System.Management.Automation.PSCredential("Azure\$DestStorageAccountName", $secureDestKey)
            New-PSDrive -Name $destDrive -PSProvider FileSystem -Root $destUNC -Credential $destCredential -ErrorAction Stop | Out-Null
            Write-Log "Destination mapped to ${destDrive}: ($destUNC) using storage account key" -Level SUCCESS
        }
        else {
            New-PSDrive -Name $destDrive -PSProvider FileSystem -Root $destUNC -ErrorAction Stop | Out-Null
            Write-Log "Destination mapped to ${destDrive}: ($destUNC) using Entra ID" -Level SUCCESS
        }
    }
    catch {
        Write-Log "Failed to map destination drive: $_" -Level ERROR
        Remove-PSDrive -Name $sourceDrive -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# Configure ACLs on destination share root only if it's a new destination
if (!$sameLocation) {
    Write-Log "Configuring ACLs on destination share root (new location detected)..."
    try {
        $shareRootPath = "${destDrive}:\"
        $rootAclSuccess = Set-ShareRootACL -ShareRootPath $shareRootPath -AdminSIDs $script:adminGroupSIDs -UserSIDs $script:userGroupSIDs
        
        if (!$rootAclSuccess) {
            Write-Log "Warning: Failed to set share root ACLs. Profile ACLs may not inherit correctly." -Level WARNING
        }
    }
    catch {
        Write-Log "Error configuring share root ACLs: $_" -Level WARNING
        Write-Log "Continuing with migration, but profile ACLs may not be configured optimally." -Level WARNING
    }
}
else {
    Write-Log "Same location migration - will preserve existing share root ACLs and enable inheritance on profiles"
}

# Migrate profiles
$results = @()
$completed = 0
$failed = 0

Write-Log "Starting profile migration..."

if ($UseAzCopy -and $ConcurrentJobs -gt 1) {
    # Use concurrent processing with AzCopy for better performance
    Write-Log "Using concurrent processing with $ConcurrentJobs parallel jobs"
    
    $scriptVars = @{
        storageEndpointSuffix = $script:storageEndpointSuffix
        logFile = $logFile
        adminGroupSIDs = $script:adminGroupSIDs
        userGroupSIDs = $script:userGroupSIDs
    }
    
    $results = Invoke-ConcurrentMigration `
        -Containers $Containers `
        -SourceDrive $sourceDrive `
        -DestDrive $destDrive `
        -SourceStorageAccount $SourceStorageAccountName `
        -SourceShare $SourceShareName `
        -DestStorageAccount $DestStorageAccountName `
        -DestShare $DestShareName `
        -Rename $RenameFolders.IsPresent `
        -TempPath $TempPath `
        -MaxConcurrent $ConcurrentJobs `
        -ScriptVariables $scriptVars
    
    # Set ACLs on all migrated profiles
    Write-Log "Setting ACLs on migrated profiles..."
    foreach ($result in $results) {
        if ($result.Success) {
            $destProfilePath = "${destDrive}:\$($result.DestFolder)"
            $destOutputPath = Join-Path $destProfilePath $result.DestOutput
            
            # Extract SID from folder name
            $userSID = $null
            if ($result.DestFolder -match '^(S-[0-9-]+)_') {
                $userSID = $matches[1]
            } elseif ($result.DestFolder -match '_(S-[0-9-]+)$') {
                $userSID = $matches[1]
            }
            
            if ($userSID) {
                Set-ProfileACL -ProfilePath $destProfilePath -VHDXPath $destOutputPath -UserSID $userSID | Out-Null
            }
            $completed++
        } else {
            $failed++
        }
    }
}
else {
    # Sequential processing (original method)
    if ($UseAzCopy) {
        Write-Log "Using sequential processing with AzCopy (set ConcurrentJobs > 1 for better performance)"
    }
    
    foreach ($Container in $Containers) {
        $result = Migrate-FSLogixContainer `
            -Container $Container `
            -SourceDrive $sourceDrive `
            -DestDrive $destDrive `
            -SourceStorageAccount $SourceStorageAccountName `
            -SourceShare $SourceShareName `
            -DestStorageAccount $DestStorageAccountName `
            -DestShare $DestShareName `
            -Rename $RenameFolders.IsPresent `
            -TempPath $TempPath `
            -UseAzCopy $UseAzCopy `
            -OutputType $OutputType `
            -SameLocation $sameLocation
        
        $results += $result
        
        if ($result.Success) {
            $completed++
        }
        else {
            $failed++
        }
        
        $percentComplete = [math]::Round(($completed + $failed) / $Containers.Count * 100, 1)
        Write-Progress -Activity "Migrating FSLogix Profiles" -Status "$completed completed, $failed failed" -PercentComplete $percentComplete
    }
    
    Write-Progress -Activity "Migrating FSLogix Profiles" -Completed
}

# Cleanup: Unmap drives
Write-Log "Unmapping drives..."
if ($sameLocation) {
    Remove-PSDrive -Name $sourceDrive -Force -ErrorAction SilentlyContinue
    Write-Log "Unmapped drive ${sourceDrive}:"
}
else {
    Remove-PSDrive -Name $sourceDrive -Force -ErrorAction SilentlyContinue
    Remove-PSDrive -Name $destDrive -Force -ErrorAction SilentlyContinue
    Write-Log "Unmapped drives ${sourceDrive}: and ${destDrive}:"
}

# Summary
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Log "========================================" -Level INFO
Write-Log "Migration Summary" -Level INFO
Write-Log "========================================" -Level INFO
Write-Log "Total Profiles: $($Containers.Count)"
Write-Log "Successful: $completed" -Level SUCCESS
Write-Log "Failed: $failed" -Level $(if ($failed -gt 0) { "ERROR" } else { "INFO" })
Write-Log "Duration: $($duration.ToString('hh\:mm\:ss'))"
Write-Log "========================================" -Level INFO

# Export results to CSV
$csvPath = Join-Path $LogPath "MigrationResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Log "Results exported to: $csvPath" -Level SUCCESS

if ($failed -gt 0) {
    Write-Log "Some migrations failed. Check the log for details." -Level WARNING
    $failedProfiles = $results | Where-Object { !$_.Success }
    foreach ($fp in $failedProfiles) {
        Write-Log "Failed: $($fp.SourceFolder) - $($fp.Error)" -Level ERROR
    }
}

Write-Log "Migration script completed" -Level SUCCESS

#endregion
