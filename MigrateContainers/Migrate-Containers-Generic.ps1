#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Migrates FSLogix profile VHD/VHDX files between generic UNC paths with format conversion and ACL management.

.DESCRIPTION
    A PowerShell script for migrating FSLogix user profile containers between any SMB file shares
    including Azure NetApp Files, Windows File Servers, DFS namespaces, and other UNC paths. The script
    performs VHD to VHDX conversion (or fixed to dynamic VHD optimization), optional folder renaming
    from SID_username to username_SID format, and sets proper NTFS permissions with ownership based on
    user SIDs.

    KEY FEATURES:
    - Works with any SMB share (Azure NetApp Files, file servers, DFS, etc.)
    - Converts fixed VHD/VHDX to dynamic, or VHD to VHDX
    - Parallel processing via runspace pool (ConcurrentProfiles)
    - Automatic ACL configuration with Creator Owner permissions
    - Optional folder renaming (SID_username → username_SID)
    - PSCredential authentication support
    - Comprehensive logging with CSV export of results
    - Progress tracking and error handling

    AUTHENTICATION:
    - Current Windows Identity (default) — no credentials required if running as authorized user
    - Explicit credentials via -SourceCredential and -DestinationCredential parameters
    - Supports different credentials for source and destination

    TRANSFER METHOD:
    - Copy-Item for all file transfers (direct SMB, no external tools required)
    - Runspace pool for profile-level parallelism (ConcurrentProfiles)
    - Temp disk used only when conversion is needed; direct copy otherwise

    PREREQUISITES:
    - Windows Server or Windows 10/11 with Hyper-V PowerShell module
    - Network connectivity to source and destination shares (SMB port 445)
    - Appropriate permissions on source and destination shares
    - Sufficient local disk space for VHD conversion temp files

    PERFORMANCE CONSIDERATIONS:
    - Profile concurrency: Default 4 parallel profile migrations
    - Network bandwidth: 1Gbps = ~100MB/s
    - Temp disk space: ~ConcurrentProfiles × largest profile size for conversion

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
    Boolean to rename profile folders from SID_username to username_SID format
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
    Requires sufficient space (~ConcurrentProfiles × largest profile size)
    Default: "$env:TEMP\FSLogixMigration"
    Required: No

.PARAMETER ConcurrentProfiles
    Number of parallel profile migrations
    Higher values = faster migration but more resource usage
    Recommended: 2-8 depending on network and CPU
    Default: 4
    Required: No

.PARAMETER OutputType
    Output virtual disk format: VHD or VHDX
    VHD: Creates dynamic VHD (useful for in-place optimization)
    VHDX: Creates dynamic VHDX (recommended for new deployments)
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
    Prerequisite   : PowerShell 5.1+, Hyper-V PowerShell Module, Modules\FSLogixMigration.psm1
    Version        : 2.0
    Date           : 2026-04-26

    DISCLAIMER:
    This Sample Code is provided for the purpose of illustration only and is not intended to be used
    in a production environment without testing. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE
    PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED
    TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.

    IMPORTANT NOTES:
    - Source VHD files remain untouched when migrating to a different location
    - Script requires elevated privileges for ACL operations
    - Test with a small batch before full production migration

    TROUBLESHOOTING:
    - "Access Denied" errors: Verify credentials and NTFS permissions
    - "Hyper-V module not found": Install with Install-WindowsFeature -Name Hyper-V-PowerShell
    - Slow performance: Adjust -ConcurrentProfiles parameter
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
    # Migration with folder renaming
    .\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\10.0.0.10\profiles" `
        -DestinationUNCPath "\\10.0.1.10\profiles" `
        -RenameFolders $true

.EXAMPLE
    # High-performance migration with increased parallelism
    .\Migrate-Containers-Generic.ps1 -SourceUNCPath "\\source\profiles" `
        -DestinationUNCPath "\\dest\profiles" `
        -ConcurrentProfiles 8

.EXAMPLE
    # In-place VHD optimization (convert fixed VHD to dynamic VHD)
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
    [bool]$RenameFolders = $false,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$PSScriptRoot\Logs",

    [Parameter(Mandatory = $false)]
    [string]$TempPath = "$env:TEMP\FSLogixMigration",

    [Parameter(Mandatory = $false)]
    [int]$ConcurrentProfiles = 4,

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

# Import utility module
$modulePath = Join-Path $PSScriptRoot "Modules\FSLogixMigration.psm1"
if (!(Test-Path $modulePath)) {
    Write-Host "ERROR: Utility module not found: $modulePath" -ForegroundColor Red
    Write-Host "Please ensure Modules\FSLogixMigration.psm1 is present relative to this script." -ForegroundColor Yellow
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
        [string]$UNCPath
    )

    try {
        Write-Log "Enumerating FSLogix profiles from $UNCPath"

        $folders = Get-ChildItem -Path $UNCPath -Directory -ErrorAction SilentlyContinue

        $Containers = @()
        foreach ($folder in $folders) {
            $vhdFiles = Get-ChildItem -Path $folder.FullName -Filter "*.vhd*" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.vhd', '.vhdx' }

            foreach ($vhd in $vhdFiles) {
                try {
                    $vhdInfo   = Get-VHD -Path $vhd.FullName -ErrorAction Stop
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
                    VHDName    = $vhd.Name
                    VHDPath    = $vhd.FullName
                    VHDSize    = $vhd.Length
                    IsDynamic  = $isDynamic
                    VhdFormat  = $vhdFormat
                }
                Write-Verbose "  $($folder.Name)\$($vhd.Name) | $vhdFormat | Dynamic=$isDynamic | $([math]::Round($vhd.Length / 1MB, 1)) MB"
            }
        }

        Write-Log "Found $($Containers.Count) VHD/VHDX files to migrate" -Level SUCCESS

        # Use @() to ensure .Count returns 0 (not $null) when no items match (PowerShell 7 compatibility)
        $dynamicCount = @($Containers | Where-Object { $_.IsDynamic }).Count
        $fixedCount   = $Containers.Count - $dynamicCount
        Write-Log "Dynamic disks: $dynamicCount, Fixed disks: $fixedCount"

        # Unary comma preserves single-element arrays across the pipeline so .Count works in the caller
        return ,$Containers
    }
    catch {
        Write-Log "Error enumerating profiles: $_" -Level ERROR
        throw
    }
}

function Invoke-ConcurrentMigration {
    param(
        [array]$Containers,
        [string]$SourceUNCPath,
        [string]$DestUNCPath,
        [bool]$Rename,
        [string]$TempPath,
        [string]$OutputType,
        [bool]$SameLocation,
        [int]$MaxConcurrent,
        [string]$LogFile,
        [string]$ModulePath,
        [bool]$ForceConversion
    )

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrent)
    $runspacePool.Open()

    # Capture preference variables to pass into each runspace explicitly.
    # Runspaces do not inherit $VerbosePreference / $DebugPreference from the parent session.
    $capturedVerbose = $VerbosePreference
    $capturedDebug   = $DebugPreference

    # Credentials are not passed to runspaces: Connect-UNCPath in the main script establishes
    # an OS-level SMB session (net use) that is accessible from all runspaces.
    # UNC paths are used directly — no drive letters needed.
    $scriptBlock = {
        param(
            $Container,
            $SourceUNCPath,
            $DestUNCPath,
            $Rename,
            $TempPath,
            $OutputType,
            $SameLocation,
            $LogFile,
            $ModulePath,
            $ForceConversion,
            $VerbosePreference,
            $DebugPreference
        )

        Import-Module $ModulePath -Force
        Set-LogFilePath -Path $LogFile

        return Migrate-FSLogixContainer `
            -Container       $Container `
            -SourceUNCPath   $SourceUNCPath `
            -DestUNCPath     $DestUNCPath `
            -Rename          $Rename `
            -TempPath        $TempPath `
            -OutputType      $OutputType `
            -SameLocation    $SameLocation `
            -ForceConversion $ForceConversion
    }

    $jobs = @()
    foreach ($Container in $Containers) {
        $ps = [powershell]::Create().AddScript($scriptBlock).AddParameters(@{
            Container       = $Container
            SourceUNCPath   = $SourceUNCPath
            DestUNCPath     = $DestUNCPath
            Rename          = $Rename
            TempPath        = $TempPath
            OutputType      = $OutputType
            SameLocation    = $SameLocation
            LogFile         = $LogFile
            ModulePath      = $ModulePath
            ForceConversion = $ForceConversion
            VerbosePreference = $capturedVerbose
            DebugPreference   = $capturedDebug
        })

        $ps.RunspacePool = $runspacePool
        $jobs += [PSCustomObject]@{
            Pipe      = $ps
            Container = $Container
            Status    = $ps.BeginInvoke()
            Collected = $false
        }
    }

    $results   = @()
    $completed = 0
    $totalJobs = $jobs.Count

    while (($jobs | Where-Object { -not $_.Collected }).Count -gt 0) {
        foreach ($job in ($jobs | Where-Object { $_.Status.IsCompleted -and !$_.Collected })) {
            # Surface any terminating errors from the runspace
            if ($job.Pipe.HadErrors) {
                foreach ($err in $job.Pipe.Streams.Error) {
                    Write-Log "[$($job.Container.FolderName)] Runspace error: $err" -Level ERROR
                }
            }
            foreach ($msg in $job.Pipe.Streams.Verbose) { Write-Verbose $msg.Message }
            foreach ($msg in $job.Pipe.Streams.Debug)   { Write-Debug   $msg.Message }
            $items = $job.Pipe.EndInvoke($job.Status)
            if ($items.Count -gt 0) {
                foreach ($item in $items) { $results += $item }
            }
            else {
                # Runspace returned nothing — treat as failure
                $results += [PSCustomObject]@{
                    Success       = $false
                    SourceFolder  = $job.Container.FolderName
                    DestFolder    = $null
                    SourceVHD     = $job.Container.VHDName
                    DestOutput    = $null
                    OriginalSize  = $job.Container.VHDSize
                    ConvertedSize = $null
                    Skipped       = $false
                    Error         = 'Runspace returned no result (check log for errors)'
                }
            }
            $job.Pipe.Dispose()
            $job.Collected = $true
            $completed++

            $pct = [math]::Round($completed / $totalJobs * 100, 1)
            Write-Progress -Activity "Migrating FSLogix Profiles" `
                           -Status "$completed of $totalJobs completed" `
                           -PercentComplete $pct
        }

        if (($jobs | Where-Object { -not $_.Status.IsCompleted }).Count -gt 0) {
            Start-Sleep -Milliseconds 500
        }
    }

    Write-Progress -Activity "Migrating FSLogix Profiles" -Completed

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
$Containers = Get-FSLogixContainers -UNCPath $SourceUNCPath

if ($Containers.Count -eq 0) {
    Write-Log "No VHD files found to migrate" -Level WARNING
    exit 0
}

Write-Log "Found $($Containers.Count) profiles to migrate"

# Authenticate to shares if explicit credentials were provided.
# Connect-UNCPath uses net use to establish an OS-level SMB session accessible
# from all runspaces — no drive letters required.
if ($SourceCredential) {
    Write-Log "Authenticating to source share with provided credentials..."
    Connect-UNCPath -UNCPath $SourceUNCPath -Credential $SourceCredential
    Write-Log "Authenticated to source share" -Level SUCCESS
}

if (!$sameLocation -and $DestinationCredential) {
    Write-Log "Authenticating to destination share with provided credentials..."
    Connect-UNCPath -UNCPath $DestinationUNCPath -Credential $DestinationCredential
    Write-Log "Authenticated to destination share" -Level SUCCESS
}

# Configure ACLs on destination share root only if it's a new destination
if (!$sameLocation) {
    Write-Log "Configuring ACLs on destination share root (new location detected)..."
    try {
        $aclResult = Set-ShareRootACL -ShareRootPath $DestinationUNCPath -AdminSIDs $AdministratorGroupSIDs -UserSIDs $UserGroupSIDs
        
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
$results   = @()
$completed = 0
$failed    = 0

Write-Log "Starting profile migration with $ConcurrentProfiles concurrent jobs..."

$results = Invoke-ConcurrentMigration `
    -Containers      $Containers `
    -SourceUNCPath   $SourceUNCPath `
    -DestUNCPath     $DestinationUNCPath `
    -Rename          $RenameFolders `
    -TempPath        $TempPath `
    -OutputType      $OutputType `
    -SameLocation    $sameLocation `
    -MaxConcurrent   $ConcurrentProfiles `
    -LogFile         $logFile `
    -ModulePath      $modulePath `
    -ForceConversion $Force

# Tally results — ACLs were already applied inside each parallel job
Write-Log "Tallying migration results..."
foreach ($result in $results) {
    if ($result.Success -and -not $result.Skipped) {
        $completed++
    }
    elseif ($result.Skipped) {
        $completed++
    }
    else {
        $failed++
    }
}

# Disconnect authenticated shares if explicit credentials were used
if ($SourceCredential) {
    Disconnect-UNCPath -UNCPath $SourceUNCPath
}
if (!$sameLocation -and $DestinationCredential) {
    Disconnect-UNCPath -UNCPath $DestinationUNCPath
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