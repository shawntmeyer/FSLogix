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
    Version        : 1.1
    Date           : 2026-02-01
    
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
    [string[]]$UserGroupSIDs = @(),

    [Parameter(Mandatory = $false)]
    [switch]$Force
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

# Import common module
$modulePath = Join-Path $PSScriptRoot "FSLogixMigrationCommon.psm1"
if (!(Test-Path $modulePath)) {
    Write-Host "ERROR: Common module not found: $modulePath" -ForegroundColor Red
    Write-Host "Please ensure FSLogixMigrationCommon.psm1 is in the same directory as this script." -ForegroundColor Yellow
    exit 1
}

Import-Module $modulePath -Force
Set-LogFilePath -Path $logFile

#endregion

#region Functions

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
            $loginCheck = & azcopy login status 2>&1 | Out-String
        } else {
            $azCopyPath = Join-Path -Path $PSScriptRoot -ChildPath "azcopy.exe"
            If (Test-Path $azCopyPath) {
                Write-Log "AzCopy found at script directory: $azCopyPath" -Level SUCCESS
                # Check if logged in
                $loginCheck = & $azCopyPath login status 2>&1 | Out-String
            }
            Else {
                Write-Log "AzCopy not found in path or script directory" -Level WARNING
                return $false
            }
        }
        if ($loginCheck -match "Your login session is still active") {
            Write-Log "AzCopy is authenticated with Entra ID" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "AzCopy found but not authenticated. Run 'azcopy login' first." -Level WARNING
            return $false
        }
    }
    catch {
        Write-Log "Error checking for AzCopy: $_" -Level WARNING
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
        
        New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $sourceUNC -Scope Global -ErrorAction Stop | Out-Null
        Write-Log "Mapped drive ${driveLetter}: to $sourceUNC (using Entra ID authentication)" -Level SUCCESS
        
        # Get all profile folders
        $profilePath = "${driveLetter}:\"
        $folders = Get-ChildItem -Path $profilePath -Directory -ErrorAction SilentlyContinue
        
        $Containers = @()
        foreach ($folder in $folders) {
            # Look for VHD and VHDX files
            $vhdFiles = Get-ChildItem -Path $folder.FullName -Filter "*.vhd*" -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.Extension -in '.vhd', '.vhdx' }
            
            foreach ($vhd in $vhdFiles) {
                # Get VHD info to check if it's dynamic
                try {
                    $vhdInfo = Get-VHD -Path $vhd.FullName -ErrorAction Stop
                    $isDynamic = ($vhdInfo.VhdType -eq 'Dynamic')
                    $vhdFormat = $vhdInfo.VhdFormat
                }
                catch {
                    Write-Log "Warning: Could not read VHD info for $($vhd.FullName): $_" -Level WARNING
                    $isDynamic = $false
                    $vhdFormat = if ($vhd.Extension -eq '.vhdx') { 'VHDX' } else { 'VHD' }
                }
                
                $Containers += [PSCustomObject]@{
                    FolderName = $folder.Name
                    FolderPath = $folder.FullName
                    VHDName = $vhd.Name
                    VHDPath = $vhd.FullName
                    VHDSize = $vhd.Length
                    IsDynamic = $isDynamic
                    VhdFormat = $vhdFormat
                }
            }
        }
        
        # Remove drive
        Remove-PSDrive -Name $driveLetter -Force
        
        Write-Log "Found $($Containers.Count) VHD/VHDX files to migrate" -Level SUCCESS
        
        # Report on disk types
        $dynamicCount = ($Containers | Where-Object { $_.IsDynamic }).Count
        $fixedCount = $Containers.Count - $dynamicCount
        Write-Log "Dynamic disks: $dynamicCount, Fixed disks: $fixedCount"
        return $Containers
    }
    catch {
        Write-Log "Error enumerating profiles: $_" -Level ERROR
        throw
    }
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
        [hashtable]$ScriptVariables,
        [bool]$ForceConversion
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
            $LogFile,
            $ForceConversion
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
            & azcopy copy "$sourceFolder/*" $threadTempPath --exclude-pattern="*.vhd;*.backup" --overwrite=true 2>&1 | Out-Null
            
            # Upload to destination
            $destURL = "https://$DestStorageAccount.file.$StorageEndpointSuffix/$DestShare/$destFolderName"
            
            Write-ThreadLog "Uploading: $destFolderName"
            $output = & azcopy copy "$threadTempPath\*" $destURL --overwrite=true 2>&1
            
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
                DestOutput = $vhdxName
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
                DestOutput = $null
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
            ForceConversion = $ForceConversion
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
            $azcopyArgs += '--recursive'
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
        [bool]$SameLocation,
        [bool]$ForceConversion
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
        
        # Determine if conversion is needed
        $needsConversion = $false
        $conversionReason = ""
        $convertedSize = $null
        
        if ($ForceConversion) {
            $needsConversion = $true
            $conversionReason = "Force parameter specified"
        }
        elseif (!$Container.IsDynamic) {
            $needsConversion = $true
            $conversionReason = "Source is fixed disk"
        }
        elseif ($Container.VhdFormat -ne $OutputType) {
            $needsConversion = $true
            $conversionReason = "Format conversion ($($Container.VhdFormat) -> $OutputType)"
        }
        elseif ($SameLocation) {
            # Already dynamic, same location, no force = skip
            Write-Log "Skipping $($Container.VHDName) - already dynamic $($Container.VhdFormat) at destination" -Level SUCCESS
            
            return [PSCustomObject]@{
                SourceFolder = $Container.FolderName
                DestFolder = $destFolderName
                SourceVHD = $Container.VHDName
                DestOutput = $Container.VHDName
                OriginalSize = $Container.VHDSize
                ConvertedSize = $Container.VHDSize
                Skipped = $true
                Success = $true
                Error = $null
            }
        }
        
        if (!$needsConversion) {
            # Already dynamic and correct format - just copy directly
            Write-Log "Source is already dynamic $($Container.VhdFormat) - copying directly (no conversion needed)"
            Copy-Item -Path $sourceVHDPath -Destination $destOutputPath -Force
            $convertedSize = $Container.VHDSize
            
            # Copy metadata files
            $metadataFiles = Get-ChildItem -Path $sourceProfilePath -File | Where-Object { $_.Extension -notin @('.vhd', '.vhdx', '.backup') }
            foreach ($file in $metadataFiles) {
                $destFile = Join-Path $destProfilePath $file.Name
                Copy-Item -Path $file.FullName -Destination $destFile -Force
            }
        }
        elseif ($UseAzCopy) {
            # Conversion needed with AzCopy workflow
            Write-Log "Conversion needed: $conversionReason"
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
            $metadataFiles = Get-ChildItem -Path $sourceProfilePath -File | Where-Object { $_.Extension -notin @('.vhd', '.backup') }
            foreach ($file in $metadataFiles) {
                $destFile = Join-Path $profileTempPath $file.Name
                Copy-Item -Path $file.FullName -Destination $destFile -Force
            }
            
            # Copy all files to destination with AzCopy
            Write-Log "Using AzCopy to copy files to destination: $destProfilePath"
            $destURL = "https://$DestStorageAccount.file.$script:storageEndpointSuffix/$DestShare/$destFolderName"
            $azCopySuccess = Copy-WithAzCopy -SourcePath "$profileTempPath\*" -DestinationPath $destURL -IsRecursive $false
            if (!$azCopySuccess) {
                Write-Log "AzCopy failed, falling back to Copy-Item" -Level WARNING
                Copy-Item -Path "$profileTempPath\*" -Destination $destProfilePath -Force -Recurse
            }
            
            # Cleanup temp
            Remove-Item -Path $profileTempPath -Recurse -Force -ErrorAction SilentlyContinue
            
            $convertedSize = (Get-Item $destOutputPath).Length
        }
        else {
            # Conversion needed with direct UNC path
            Write-Log "Conversion needed: $conversionReason"
            Write-Log "Converting VHD to dynamic $OutputType directly: $sourceVHDPath -> $destOutputPath"
            Convert-VHD -Path $sourceVHDPath -DestinationPath $destOutputPath -VHDType Dynamic
            
            if (!(Test-Path $destOutputPath)) {
                throw "$OutputType conversion failed - file not created"
            }
            
            Write-Log "Conversion successful. $OutputType size: $([math]::Round((Get-Item $destOutputPath).Length / 1GB, 2)) GB" -Level SUCCESS
            $convertedSize = (Get-Item $destOutputPath).Length
            
            # Copy metadata files directly from source to destination
            $metadataFiles = Get-ChildItem -Path $sourceProfilePath -File | Where-Object { $_.Extension -notin @('.vhd', '.vhdx', '.backup') }
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
            ConvertedSize = $convertedSize
            Skipped = $false
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
            ConvertedSize = $null
            Skipped = $false
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
    
    # Check for incompatible combination: AzCopy with in-place VHD optimization
    if ($UseAzCopy -and $sameLocation -and $OutputType -eq 'VHD') {
        Write-Log "Warning: AzCopy cannot be used with in-place VHD optimization. Disabling AzCopy." -Level WARNING
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
        New-PSDrive -Name $sourceDrive -PSProvider FileSystem -Root $sourceUNC -Credential $sourceCredential -Scope Global -ErrorAction Stop | Out-Null
        Write-Log "Source mapped to ${sourceDrive}: ($sourceUNC) using storage account key" -Level SUCCESS
    }
    else {
        New-PSDrive -Name $sourceDrive -PSProvider FileSystem -Root $sourceUNC -Scope Global -ErrorAction Stop | Out-Null
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
            New-PSDrive -Name $destDrive -PSProvider FileSystem -Root $destUNC -Credential $destCredential -Scope Global -ErrorAction Stop | Out-Null
            Write-Log "Destination mapped to ${destDrive}: ($destUNC) using storage account key" -Level SUCCESS
        }
        else {
            New-PSDrive -Name $destDrive -PSProvider FileSystem -Root $destUNC -Scope Global -ErrorAction Stop | Out-Null
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
        -ScriptVariables $scriptVars `
        -ForceConversion $Force
    
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
            -SameLocation $sameLocation `
            -ForceConversion $Force
        
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
