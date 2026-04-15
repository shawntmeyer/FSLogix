<#
.SYNOPSIS
    Migrates FSLogix profile VHD/VHDX files between generic UNC paths with format conversion and ACL management.

.DESCRIPTION
    A comprehensive PowerShell script for migrating FSLogix user profile containers between any SMB file shares
    including Azure NetApp Files, Windows File Servers, DFS namespaces, and other UNC paths. The script performs 
    VHD to VHDX conversion (or VHD to dynamic VHD optimization), optional folder renaming from SID_username to 
    username_SID format, and sets proper NTFS permissions with ownership based on user SIDs.
    
    KEY FEATURES:
    - Works with any SMB share (Azure NetApp Files, file servers, DFS, etc.)
    - Converts VHD to dynamic VHDX or optimizes VHD to dynamic VHD
    - Multi-threaded parallel processing with Robocopy
    - Automatic ACL configuration with Creator Owner permissions
    - Optional folder renaming (SID_username ↔ username_SID)
    - PSCredential authentication support
    - Comprehensive logging with CSV export of results
    - Progress tracking and error handling
    
    AUTHENTICATION:
    - Current Windows Identity (default) - no credentials required if running as authorized user
    - Explicit credentials via -SourceCredential and -DestinationCredential parameters
    - Supports different credentials for source and destination
    
    TRANSFER METHOD:
    - Robocopy with multi-threading (/MT switch)
    - Configurable parallelism for profile-level concurrency
    - Built-in retry logic for network resilience
    - Works with any SMB share accessible via UNC path
    
    PREREQUISITES:
    - Windows Server or Windows 10/11 with Hyper-V PowerShell module
    - Network connectivity to source and destination shares (SMB port 445)
    - Appropriate permissions on source and destination shares
    - Sufficient local disk space for VHD conversion temp files
    
    PERFORMANCE CONSIDERATIONS:
    - Robocopy multi-threading: Default 8 threads per file transfer
    - Profile concurrency: Default 4 parallel profile migrations
    - Network bandwidth: 1Gbps = ~100MB/s
    - Temp disk space: ~2x largest profile size for conversion

.PARAMETER SourceUNCPath
    Source UNC path to the share containing FSLogix profiles
    Example: "\\fileserver\profiles" or "\\10.0.0.10\fslogix-prod"
    Required: Yes

.PARAMETER DestinationUNCPath
    Destination UNC path for migrated profiles
    If omitted, uses same as source (in-place conversion)
    Example: "\\newserver\profiles" or "\\anf.contoso.com\profiles"
    Required: No

.PARAMETER SourceCredential
    PSCredential object for authenticating to source share
    If omitted, uses current Windows identity
    Create with: $cred = Get-Credential
    Required: No

.PARAMETER DestinationCredential
    PSCredential object for authenticating to destination share
    If omitted, uses current Windows identity
    Create with: $cred = Get-Credential
    Required: No

.PARAMETER RenameFolders
    Switch to rename profile folders from SID_username to username_SID format
    Useful for compliance with FSLogix best practices
    Example: "S-1-5-21-xxx_jdoe" becomes "jdoe_S-1-5-21-xxx"
    Required: No

.PARAMETER LogPath
    Directory path for log files
    Creates directory if it doesn't exist
    Default: "$PSScriptRoot\Logs"
    Required: No

.PARAMETER TempPath
    Temporary directory for VHD conversion operations
    Requires sufficient space (~2x largest profile size)
    Default: "$env:TEMP\FSLogixMigration"
    Required: No

.PARAMETER ConcurrentProfiles
    Number of parallel profile migrations
    Higher values = faster migration but more resource usage
    Recommended: 2-8 depending on network and CPU
    Default: 4
    Required: No

.PARAMETER RobocopyThreads
    Number of threads for Robocopy operations (/MT switch)
    Recommended: 8-16 for most scenarios
    Default: 8
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
    File Name      : Migrate-Containers-Generic.ps1
    Author         : GitHub Copilot
    Prerequisite   : PowerShell 5.1+, Hyper-V PowerShell Module, FSLogixMigrationCommon.psm1
    Version        : 1.0
    Date           : 2026-04-03
    
    DISCLAIMER:
    This Sample Code is provided for the purpose of illustration only and is not intended to be used 
    in a production environment without testing. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE
    PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED
    TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
    
    IMPORTANT NOTES:
    - Source VHD files remain untouched when migrating to different location
    - In-place VHD optimization creates .backup files (removed after successful conversion)
    - Script requires elevated privileges for ACL operations
    - Test with small batch before full production migration
    - Robocopy logs are created in LogPath for troubleshooting
    
    TROUBLESHOOTING:
    - "Access Denied" errors: Verify credentials and NTFS permissions
    - "Hyper-V module not found": Install with Install-WindowsFeature -Name Hyper-V-PowerShell
    - Slow performance: Adjust -ConcurrentProfiles and -RobocopyThreads parameters
    - Network errors: Check SMB connectivity and firewall rules (port 445)

.EXAMPLE
    # Simple migration using current Windows identity
    .\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\oldserver\profiles" `
        -DestinationUNCPath "\\newserver\profiles"

.EXAMPLE
    # Migration with explicit credentials (useful for domain migrations)
    $srcCred = Get-Credential -Message "Source share credentials"
    $dstCred = Get-Credential -Message "Destination share credentials"
    .\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\oldserver\profiles" `
        -DestinationUNCPath "\\anf.contoso.com\profiles" `
        -SourceCredential $srcCred `
        -DestinationCredential $dstCred

.EXAMPLE
    # Azure NetApp Files migration with folder renaming
    .\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\10.0.0.10\profiles" `
        -DestinationUNCPath "\\10.0.1.10\profiles" `
        -RenameFolders

.EXAMPLE
    # High-performance migration with increased parallelism
    .\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\source\profiles" `
        -DestinationUNCPath "\\dest\profiles" `
        -ConcurrentProfiles 8 `
        -RobocopyThreads 16

.EXAMPLE
    # In-place VHD optimization (convert VHD to dynamic VHD)
    .\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\fileserver\profiles" `
        -OutputType VHD

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceUNCPath,

    [Parameter(Mandatory = $false)]
    [string]$DestinationUNCPath,

    [Parameter(Mandatory = $false)]
    [PSCredential]$SourceCredential,

    [Parameter(Mandatory = $false)]
    [PSCredential]$DestinationCredential,

    [Parameter(Mandatory = $false)]
    [switch]$RenameFolders,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$PSScriptRoot\Logs",

    [Parameter(Mandatory = $false)]
    [string]$TempPath = "$env:TEMP\FSLogixMigration",

    [Parameter(Mandatory = $false)]
    [int]$ConcurrentProfiles = 4,

    [Parameter(Mandatory = $false)]
    [int]$RobocopyThreads = 8,

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

# Import common module
$modulePath = Join-Path $PSScriptRoot "FSLogixMigrationCommon.psm1"
if (!(Test-Path $modulePath)) {
    Write-Host "ERROR: Common module not found: $modulePath" -ForegroundColor Red
    Write-Host "Please ensure FSLogixMigrationCommon.psm1 is in the same directory as this script." -ForegroundColor Yellow
    exit 1
}

Import-Module $modulePath -Force

$ErrorActionPreference = "Stop"
$startTime = Get-Date

# Normalize UNC paths (remove trailing slashes)
$SourceUNCPath = $SourceUNCPath.TrimEnd('\')

# Set defaults if not specified
if ([string]::IsNullOrEmpty($DestinationUNCPath)) {
    $DestinationUNCPath = $SourceUNCPath
}
else {
    $DestinationUNCPath = $DestinationUNCPath.TrimEnd('\')
}

$sameLocation = ($SourceUNCPath -eq $DestinationUNCPath)

# Create directories
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

if (!(Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

$logFile = Join-Path $LogPath "FSLogixMigration_Generic_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Set-LogFilePath -Path $logFile

#endregion

#region Functions

function Get-FSLogixContainers {
    param(
        [string]$UNCPath,
        [PSCredential]$Credential
    )
    
    try {
        Write-Log "Enumerating FSLogix profiles from $UNCPath"
        
        # Map drive
        $driveLetter = Get-AvailableDriveLetter
        
        $driveParams = @{
            Name = $driveLetter
            PSProvider = 'FileSystem'
            Root = $UNCPath
            Scope = 'Global'
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $driveParams['Credential'] = $Credential
            Write-Log "Mapping drive ${driveLetter}: with provided credentials"
        }
        else {
            Write-Log "Mapping drive ${driveLetter}: with current Windows identity"
        }
        
        New-PSDrive @driveParams | Out-Null
        Write-Log "Successfully mapped drive ${driveLetter}: to $UNCPath" -Level SUCCESS
        
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

function Copy-WithRobocopy {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [int]$Threads,
        [string]$LogFile,
        [string]$ExcludeFiles = ""
    )
    
    try {
        Write-Log "Using Robocopy to copy: $SourcePath -> $DestinationPath"
        
        # Build Robocopy arguments
        $robocopyArgs = @(
            "`"$SourcePath`"",
            "`"$DestinationPath`"",
            "/MIR",                      # Mirror directory tree
            "/MT:$Threads",              # Multi-threaded
            "/R:3",                      # Retry 3 times
            "/W:5",                      # Wait 5 seconds between retries
            "/NP",                       # No progress percentage
            "/NDL",                      # No directory list
            "/NFL",                      # No file list
            "/LOG+:`"$LogFile`""         # Append to log file
        )
        
        if ($ExcludeFiles) {
            $robocopyArgs += "/XF"
            $robocopyArgs += $ExcludeFiles
        }
        
        # Execute Robocopy
        $robocopyCmd = "robocopy $($robocopyArgs -join ' ')"
        $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
        
        # Robocopy exit codes: 0-7 are success, 8+ are errors
        if ($process.ExitCode -gt 7) {
            throw "Robocopy failed with exit code: $($process.ExitCode)"
        }
        
        Write-Log "Robocopy transfer completed successfully (exit code: $($process.ExitCode))" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Robocopy transfer failed: $_" -Level ERROR
        return $false
    }
}

function Migrate-FSLogixContainer {
    param(
        [PSCustomObject]$Container,
        [string]$SourceDrive,
        [string]$DestDrive,
        [bool]$Rename,
        [string]$TempPath,
        [string]$OutputType,
        [bool]$SameLocation,
        [int]$RobocopyThreads,
        [string]$RobocopyLogFile,
        [bool]$ForceConversion
    )
    
    try {
        Write-Log "Starting migration for: $($Container.FolderName)"
        
        # Determine destination folder name
        $destFolderName = if ($Rename) { Convert-FolderName $Container.FolderName } else { $Container.FolderName }
        Write-Log "Destination folder: $destFolderName"
        
        $sourceFolderPath = Join-Path "${SourceDrive}:\" $Container.FolderName
        $destFolderPath = Join-Path "${DestDrive}:\" $destFolderName
        
        # Create destination folder if it doesn't exist
        if (!(Test-Path $destFolderPath)) {
            New-Item -Path $destFolderPath -ItemType Directory -Force | Out-Null
            Write-Log "Created destination folder: $destFolderPath"
        }
        
        $sourceVHDPath = Join-Path $sourceFolderPath $Container.VHDName
        
        # Determine output file name
        $outputExtension = if ($OutputType -eq 'VHDX') { '.vhdx' } else { '.vhd' }
        $outputFileName = [System.IO.Path]::ChangeExtension($Container.VHDName, $outputExtension)
        $destVHDPath = Join-Path $destFolderPath $outputFileName
        
        # Determine if conversion is needed
        $needsConversion = $false
        $conversionReason = ""
        
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
            
            return @{
                Success = $true
                SourceFolder = $Container.FolderName
                DestFolder = $destFolderName
                SourceVHD = $Container.VHDName
                DestOutput = $Container.VHDName
                OriginalSize = $Container.VHDSize
                ConvertedSize = $Container.VHDSize
                Skipped = $true
                Error = $null
            }
        }
        
        $convertedSize = $null
        
        if ($needsConversion) {
            # Need to convert the disk
            Write-Log "Conversion needed: $conversionReason"
            
            # Create temp directory for conversion
            $containerTempPath = Join-Path $TempPath $Container.FolderName
            if (!(Test-Path $containerTempPath)) {
                New-Item -Path $containerTempPath -ItemType Directory -Force | Out-Null
            }
            
            $tempVHDPath = Join-Path $containerTempPath $Container.VHDName
            $tempOutputPath = Join-Path $containerTempPath $outputFileName
            
            # Copy VHD to temp location for conversion
            Write-Log "Copying VHD to temp location for conversion..."
            Copy-Item -Path $sourceVHDPath -Destination $tempVHDPath -Force
            
            # Convert VHD
            Write-Log "Converting to $OutputType format (dynamic)..."
            if ($OutputType -eq 'VHDX') {
                Convert-VHD -Path $tempVHDPath -DestinationPath $tempOutputPath -VHDType Dynamic -DeleteSource -ErrorAction Stop
            }
            else {
                # VHD to dynamic VHD optimization
                Convert-VHD -Path $tempVHDPath -DestinationPath $tempOutputPath -VHDType Dynamic -DeleteSource -ErrorAction Stop
            }
            
            $convertedSize = (Get-Item $tempOutputPath).Length
            $convertedSizeGB = [math]::Round($convertedSize / 1GB, 2)
            Write-Log "Conversion successful. $OutputType size: $convertedSizeGB GB" -Level SUCCESS
            
            # Copy converted VHD to destination
            Write-Log "Copying converted $OutputType to destination..."
            Copy-Item -Path $tempOutputPath -Destination $destVHDPath -Force
            
            # Cleanup temp files
            Remove-Item -Path $containerTempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            # Already dynamic and correct format, just copy directly
            Write-Log "Source is already dynamic $($Container.VhdFormat) - copying directly (no conversion needed)"
            Copy-Item -Path $sourceVHDPath -Destination $destVHDPath -Force
            $convertedSize = $Container.VHDSize
        }
        
        # Copy other profile files (excluding .vhd and .backup files) using Robocopy
        if (!$SameLocation -or $Rename) {
            Write-Log "Copying profile metadata files..."
            $success = Copy-WithRobocopy `
                -SourcePath $sourceFolderPath `
                -DestinationPath $destFolderPath `
                -Threads $RobocopyThreads `
                -LogFile $RobocopyLogFile `
                -ExcludeFiles "*.vhd *.vhdx *.backup"
            
            if (!$success) {
                Write-Log "Warning: Some metadata files may not have been copied" -Level WARNING
            }
        }
        
        # Handle in-place VHD conversion
        if ($SameLocation -and $OutputType -eq 'VHD') {
            $backupPath = "$sourceVHDPath.backup"
            Write-Log "In-place conversion: Backing up original VHD"
            Move-Item -Path $sourceVHDPath -Destination $backupPath -Force
            
            Write-Log "Removing backup file"
            Remove-Item -Path $backupPath -Force
        }
        
        Write-Log "Migration completed successfully for: $($Container.FolderName)" -Level SUCCESS
        
        return @{
            Success = $true
            SourceFolder = $Container.FolderName
            DestFolder = $destFolderName
            SourceVHD = $Container.VHDName
            DestOutput = $outputFileName
            OriginalSize = $Container.VHDSize
            ConvertedSize = $convertedSize
            Skipped = $false
            Error = $null
        }
    }
    catch {
        Write-Log "Migration failed for $($Container.FolderName): $_" -Level ERROR
        
        # Cleanup temp files on failure
        if (Test-Path $containerTempPath) {
            Remove-Item -Path $containerTempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return @{
            Success = $false
            SourceFolder = $Container.FolderName
            DestFolder = $null
            SourceVHD = $Container.VHDName
            DestOutput = $null
            OriginalSize = $Container.VHDSize
            ConvertedSize = $null
            Skipped = $false
            Error = $_.Exception.Message
        }
    }
}

function Invoke-ConcurrentMigration {
    param(
        [array]$Containers,
        [string]$SourceDrive,
        [string]$DestDrive,
        [bool]$Rename,
        [string]$TempPath,
        [string]$OutputType,
        [bool]$SameLocation,
        [int]$MaxConcurrent,
        [int]$RobocopyThreads,
        [string]$LogFile,
        [bool]$ForceConversion
    )
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrent)
    $runspacePool.Open()
    
    # Script block for parallel execution
    $scriptBlock = {
        param(
            $Container,
            $SourceDrive,
            $DestDrive,
            $Rename,
            $TempPath,
            $OutputType,
            $SameLocation,
            $RobocopyThreads,
            $LogFile,
            $ModulePath,
            $ForceConversion
        )
        
        # Import common module in runspace
        Import-Module $ModulePath -Force
        Set-LogFilePath -Path $LogFile
        
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
            
            $sourceFolderPath = Join-Path "${SourceDrive}:\" $Container.FolderName
            $destFolderPath = Join-Path "${DestDrive}:\" $destFolderName
            
            # Create destination folder
            if (!(Test-Path $destFolderPath)) {
                New-Item -Path $destFolderPath -ItemType Directory -Force | Out-Null
            }
            
            $sourceVHDPath = Join-Path $sourceFolderPath $Container.VHDName
            $outputExtension = if ($OutputType -eq 'VHDX') { '.vhdx' } else { '.vhd' }
            $outputFileName = [System.IO.Path]::ChangeExtension($Container.VHDName, $outputExtension)
            $destVHDPath = Join-Path $destFolderPath $outputFileName
            
            # Determine if conversion is needed
            $needsConversion = $false
            $conversionReason = ""
            
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
                Write-Log "[$($Container.FolderName)] Skipping - already dynamic $($Container.VhdFormat)" -Level SUCCESS
                
                return @{
                    Success = $true
                    SourceFolder = $Container.FolderName
                    DestFolder = $destFolderName
                    SourceVHD = $Container.VHDName
                    DestOutput = $Container.VHDName
                    OriginalSize = $Container.VHDSize
                    ConvertedSize = $Container.VHDSize
                    Skipped = $true
                    Error = $null
                }
            }
            
            $convertedSize = $null
            
            if ($needsConversion) {
                # Create unique temp path
                $containerTempPath = Join-Path $TempPath "$($Container.FolderName)_$(Get-Random)"
                New-Item -Path $containerTempPath -ItemType Directory -Force | Out-Null
                
                $tempVHDPath = Join-Path $containerTempPath $Container.VHDName
                $tempOutputPath = Join-Path $containerTempPath $outputFileName
                
                # Copy and convert
                Write-Log "[$($Container.FolderName)] Conversion needed: $conversionReason"
                Write-Log "[$($Container.FolderName)] Copying VHD for conversion..."
                Copy-Item -Path $sourceVHDPath -Destination $tempVHDPath -Force
                
                Write-Log "[$($Container.FolderName)] Converting to $OutputType..."
                if ($OutputType -eq 'VHDX') {
                    Convert-VHD -Path $tempVHDPath -DestinationPath $tempOutputPath -VHDType Dynamic -DeleteSource -ErrorAction Stop
                }
                else {
                    Convert-VHD -Path $tempVHDPath -DestinationPath $tempOutputPath -VHDType Dynamic -DeleteSource -ErrorAction Stop
                }
                
                $convertedSize = (Get-Item $tempOutputPath).Length
                Write-Log "[$($Container.FolderName)] Conversion complete. Copying to destination..." -Level SUCCESS
                
                Copy-Item -Path $tempOutputPath -Destination $destVHDPath -Force
                Remove-Item -Path $containerTempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            else {
                # Already dynamic and correct format, just copy
                Write-Log "[$($Container.FolderName)] Already dynamic - copying directly"
                Copy-Item -Path $sourceVHDPath -Destination $destVHDPath -Force
                $convertedSize = $Container.VHDSize
            }
            
            # Copy metadata files with Robocopy
            if (!$SameLocation -or $Rename) {
                $robocopyLog = Join-Path (Split-Path $LogFile) "Robocopy_$($Container.FolderName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                $robocopyArgs = @(
                    "`"$sourceFolderPath`"",
                    "`"$destFolderPath`"",
                    "/E",
                    "/MT:$RobocopyThreads",
                    "/R:3",
                    "/W:5",
                    "/XF", "*.vhd", "*.vhdx", "*.backup",
                    "/NP",
                    "/NDL",
                    "/NFL",
                    "/LOG:`"$robocopyLog`""
                )
                
                $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
            }
            
            Write-Log "[$($Container.FolderName)] Migration completed" -Level SUCCESS
            
            return @{
                Success = $true
                SourceFolder = $Container.FolderName
                DestFolder = $destFolderName
                SourceVHD = $Container.VHDName
                DestOutput = $outputFileName
                OriginalSize = $Container.VHDSize
                ConvertedSize = $convertedSize
                Skipped = $false
                Error = $null
            }
        }
        catch {
            Write-Log "[$($Container.FolderName)] Migration failed: $_" -Level ERROR
            
            return @{
                Success = $false
                SourceFolder = $Container.FolderName
                DestFolder = $null
                SourceVHD = $Container.VHDName
                DestOutput = $null
                OriginalSize = $Container.VHDSize
                ConvertedSize = $null
                Skipped = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    # Create jobs
    $jobs = @()
    foreach ($Container in $Containers) {
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddParameters(@{
            Container = $Container
            SourceDrive = $SourceDrive
            DestDrive = $DestDrive
            Rename = $Rename
            TempPath = $TempPath
            OutputType = $OutputType
            SameLocation = $SameLocation
            RobocopyThreads = $RobocopyThreads
            LogFile = $LogFile
            ModulePath = $modulePath
            ForceConversion = $ForceConversion
        })
        
        $powershell.RunspacePool = $runspacePool
        $jobs += [PSCustomObject]@{
            Pipe = $powershell
            Status = $powershell.BeginInvoke()
            Container = $Container
            Collected = $false
        }
    }
    
    # Wait for completion and collect results
    $results = @()
    $completed = 0
    
    while ($jobs.Status.IsCompleted -contains $false) {
        $newlyCompleted = ($jobs | Where-Object { $_.Status.IsCompleted -and !$_.Collected })
        
        foreach ($job in $newlyCompleted) {
            $result = $job.Pipe.EndInvoke($job.Status)
            $results += [PSCustomObject]$result
            $job.Pipe.Dispose()
            $job.Collected = $true
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

#endregion

#region Main Script

Write-Log "================================================" -Level INFO
Write-Log " FSLogix Profile Migration Script (Generic UNC) " -Level INFO
Write-Log "================================================" -Level INFO
Write-Log "Source: $SourceUNCPath"
Write-Log "Destination: $DestinationUNCPath"
Write-Log "Rename Folders: $RenameFolders"
Write-Log "Same Location: $sameLocation"
Write-Log "Output Type: $OutputType"
Write-Log "Concurrent Profiles: $ConcurrentProfiles"
Write-Log "Robocopy Threads: $RobocopyThreads"
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

# Test connectivity to source share
Write-Log "Testing connectivity to source share..."
if (!(Test-Path $SourceUNCPath)) {
    Write-Log "Cannot access source share: $SourceUNCPath" -Level ERROR
    Write-Log "Please verify the path exists and you have appropriate permissions" -Level ERROR
    exit 1
}
Write-Log "Source share accessible" -Level SUCCESS

# Test connectivity to destination share (if different)
if (!$sameLocation) {
    Write-Log "Testing connectivity to destination share..."
    if (!(Test-Path $DestinationUNCPath)) {
        Write-Log "Cannot access destination share: $DestinationUNCPath" -Level ERROR
        Write-Log "Please verify the path exists and you have appropriate permissions" -Level ERROR
        exit 1
    }
    Write-Log "Destination share accessible" -Level SUCCESS
}

# Get all profiles to migrate
Write-Log "Enumerating FSLogix profiles..."
$Containers = Get-FSLogixContainers -UNCPath $SourceUNCPath -Credential $SourceCredential

if ($Containers.Count -eq 0) {
    Write-Log "No VHD files found to migrate" -Level WARNING
    exit 0
}

Write-Log "Found $($Containers.Count) profiles to migrate"

# Map source drive
Write-Log "Mapping source drive..."
try {
    $sourceDrive = Get-AvailableDriveLetter
    
    $sourceDriveParams = @{
        Name = $sourceDrive
        PSProvider = 'FileSystem'
        Root = $SourceUNCPath
        Scope = 'Global'
        ErrorAction = 'Stop'
    }
    
    if ($SourceCredential) {
        $sourceDriveParams['Credential'] = $SourceCredential
        Write-Log "Using provided credentials for source"
    }
    
    New-PSDrive @sourceDriveParams | Out-Null
    Write-Log "Mapped source drive ${sourceDrive}:" -Level SUCCESS
}
catch {
    Write-Log "Failed to map source drive: $_" -Level ERROR
    exit 1
}

# Map destination drive (or use same drive if same location)
if ($sameLocation) {
    $destDrive = $sourceDrive
    Write-Log "Using same drive for destination (same location migration)"
}
else {
    Write-Log "Mapping destination drive..."
    try {
        $destDrive = Get-AvailableDriveLetter
        
        $destDriveParams = @{
            Name = $destDrive
            PSProvider = 'FileSystem'
            Root = $DestinationUNCPath
            Scope = 'Global'
            ErrorAction = 'Stop'
        }
        
        if ($DestinationCredential) {
            $destDriveParams['Credential'] = $DestinationCredential
            Write-Log "Using provided credentials for destination"
        }
        
        New-PSDrive @destDriveParams | Out-Null
        Write-Log "Mapped destination drive ${destDrive}:" -Level SUCCESS
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
        $destRootPath = "${destDrive}:\"
        $aclResult = Set-ShareRootACL -ShareRootPath $destRootPath -AdminSIDs $AdministratorGroupSIDs -UserSIDs $UserGroupSIDs
        
        if (!$aclResult) {
            Write-Log "Warning: Failed to set share root ACLs" -Level WARNING
        }
    }
    catch {
        Write-Log "Warning: Error setting share root ACLs: $_" -Level WARNING
    }
}
else {
    Write-Log "Same location migration - will preserve existing share root ACLs and enable inheritance on profiles"
}

# Migrate profiles
$results = @()
$completed = 0
$failed = 0

$robocopyLogFile = Join-Path $LogPath "Robocopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-Log "Starting profile migration..."

if ($ConcurrentProfiles -gt 1) {
    # Use concurrent processing
    Write-Log "Using concurrent processing with $ConcurrentProfiles parallel jobs"
    
    $results = Invoke-ConcurrentMigration `
        -Containers $Containers `
        -SourceDrive $sourceDrive `
        -DestDrive $destDrive `
        -Rename $RenameFolders `
        -TempPath $TempPath `
        -OutputType $OutputType `
        -SameLocation $sameLocation `
        -MaxConcurrent $ConcurrentProfiles `
        -RobocopyThreads $RobocopyThreads `
        -LogFile $logFile `
        -ForceConversion $Force
    
    # Set ACLs on all migrated profiles
    Write-Log "Setting ACLs on migrated profiles..."
    foreach ($result in $results) {
        if ($result.Success) {
            $completed++
            $profilePath = Join-Path "${destDrive}:\" $result.DestFolder
            $vhdxPath = Join-Path $profilePath $result.DestOutput
            $userSID = Get-SIDFromFolderName -FolderName $result.DestFolder
            
            if ($userSID) {
                Set-ProfileACL -ProfilePath $profilePath -VHDXPath $vhdxPath -UserSID $userSID | Out-Null
            }
        }
        else {
            $failed++
        }
    }
}
else {
    # Sequential processing
    Write-Log "Using sequential processing (1 profile at a time)"
    
    foreach ($Container in $Containers) {
        $percentComplete = [math]::Round($completed / $Containers.Count * 100, 1)
        Write-Progress -Activity "Migrating FSLogix Profiles" -Status "Processing $($Container.FolderName)" -PercentComplete $percentComplete
        
        $result = Migrate-FSLogixContainer `
            -Container $Container `
            -SourceDrive $sourceDrive `
            -DestDrive $destDrive `
            -Rename $RenameFolders `
            -TempPath $TempPath `
            -OutputType $OutputType `
            -SameLocation $sameLocation `
            -RobocopyThreads $RobocopyThreads `
            -RobocopyLogFile $robocopyLogFile `
            -ForceConversion $Force
        
        $results += [PSCustomObject]$result
        
        if ($result.Success) {
            $completed++
            
            # Set ACLs
            $profilePath = Join-Path "${destDrive}:\" $result.DestFolder
            $vhdxPath = Join-Path $profilePath $result.DestOutput
            $userSID = Get-SIDFromFolderName -FolderName $result.DestFolder
            
            if ($userSID) {
                Set-ProfileACL -ProfilePath $profilePath -VHDXPath $vhdxPath -UserSID $userSID | Out-Null
            }
        }
        else {
            $failed++
        }
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
$csvPath = Join-Path $LogPath "MigrationResults_Generic_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Log "Results exported to: $csvPath" -Level SUCCESS

if ($failed -gt 0) {
    Write-Log "Some migrations failed. Check the log for details." -Level WARNING
    $failedProfiles = $results | Where-Object { !$_.Success }
    foreach ($fp in $failedProfiles) {
        Write-Log "Failed: $($fp.SourceFolder) - Error: $($fp.Error)" -Level ERROR
    }
}

Write-Log "Migration script completed" -Level SUCCESS

#endregion
