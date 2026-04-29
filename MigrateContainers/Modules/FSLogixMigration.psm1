<#
.SYNOPSIS
    Utility function library for FSLogix profile container migration scripts.

.DESCRIPTION
    Shared utility functions used by the FSLogix migration script suite:
    Migrate-Containers-AzureFiles.ps1 and Migrate-Containers-Generic.ps1.
    Covers logging, drive letter allocation, folder naming, SID extraction,
    ACL management, VHD conversion, and per-profile migration logic.

.NOTES
    File Name      : FSLogixMigration.psm1
    Location       : Modules\FSLogixMigration.psm1
    Author         : GitHub Copilot
    Prerequisite   : PowerShell 5.1+
    Version        : 2.0
    Date           : 2026-04-26
#>

# Module-level variable for log file path (set by calling script)
$script:LogFilePath = $null

function Set-LogFilePath {
    <#
    .SYNOPSIS
        Sets the log file path for the Write-Log function.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $script:LogFilePath = $Path
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes log messages to console and file.
    
    .PARAMETER Message
        The message to log.
    
    .PARAMETER Level
        Log level: INFO, WARNING, ERROR, or SUCCESS.
    #>
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
    
    # Write to file if path is set
    if ($script:LogFilePath) {
        Add-Content -Path $script:LogFilePath -Value $logMessage
    }
}

function Get-AvailableDriveLetter {
    <#
    .SYNOPSIS
        Returns an available drive letter (Z-A).
    
    .DESCRIPTION
        Scans from Z to A for an available drive letter not currently in use.
    
    .OUTPUTS
        System.Char - An available drive letter.
    #>
    $used = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
    foreach ($letter in 90..65) {  # Z to A
        $drive = [char]$letter
        if ($drive -notin $used) {
            return $drive
        }
    }
    throw "No available drive letters"
}

function Convert-FolderName {
    <#
    .SYNOPSIS
        Converts folder name between SID_username and username_SID formats.
    
    .PARAMETER FolderName
        The folder name to convert.
    
    .OUTPUTS
        System.String - Converted folder name or original if no pattern match.
    #>
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
    <#
    .SYNOPSIS
        Extracts user SID from FSLogix folder name.
    
    .PARAMETER FolderName
        The folder name (either SID_username or username_SID format).
    
    .OUTPUTS
        System.String - The SID extracted from folder name, or $null if not found.
    #>
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

function Connect-UNCPath {
    <#
    .SYNOPSIS
        Authenticates to a UNC path using explicit credentials via net use.

    .DESCRIPTION
        Establishes an OS-level SMB session so the UNC path is accessible from all
        runspaces and threads in the current process. No drive letter is allocated.
        Has no effect when called without credentials (current identity is used).

    .PARAMETER UNCPath
        The UNC share root to authenticate against (e.g. \\server\share).

    .PARAMETER Credential
        PSCredential to authenticate with.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$UNCPath,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential
    )

    $netCred = $Credential.GetNetworkCredential()
    $user    = if ($netCred.Domain) { "$($netCred.Domain)\$($netCred.UserName)" } else { $netCred.UserName }

    $output = net use $UNCPath $netCred.Password /user:$user /persistent:no 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "net use authentication failed for ${UNCPath}: $output"
    }
}

function Disconnect-UNCPath {
    <#
    .SYNOPSIS
        Removes an OS-level SMB session established by Connect-UNCPath.

    .PARAMETER UNCPath
        The UNC share root to disconnect (e.g. \\server\share).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$UNCPath
    )

    net use $UNCPath /delete /y 2>&1 | Out-Null
}

function Test-HyperVModule {
    <#
    .SYNOPSIS
        Checks if Hyper-V PowerShell module is available and loads it.
    
    .OUTPUTS
        System.Boolean - $true if module loaded successfully, $false otherwise.
    #>
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

function Set-ShareRootACL {
    <#
    .SYNOPSIS
        Configures ACLs on the share root for FSLogix profiles.
    
    .PARAMETER ShareRootPath
        Path to the share root directory.
    
    .PARAMETER AdminSIDs
        Array of administrator group SIDs to grant Full Control.
    
    .PARAMETER UserSIDs
        Array of user group SIDs to grant Modify access (this folder only).
        If empty, uses Authenticated Users (S-1-5-11).
    
    .OUTPUTS
        System.Boolean - $true if successful, $false otherwise.
    #>
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
        
        # Pre-compute InheritanceFlags combinations to avoid PowerShell parsing issues
        # with -bor inside multi-line New-Object constructor arguments
        $inheritAllFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        
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
            $inheritAllFlags,
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
                    $inheritAllFlags,
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
            $inheritAllFlags,
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
    <#
    .SYNOPSIS
        Sets ownership and inheritance on a profile folder.
    
    .PARAMETER ProfilePath
        Path to the profile folder.
    
    .PARAMETER VHDXPath
        Path to the VHDX file within the profile folder.
    
    .PARAMETER UserSID
        User SID to set as owner.
    
    .OUTPUTS
        System.Boolean - $true if successful, $false otherwise.
    #>
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
    <#
    .SYNOPSIS
        Migrates a single FSLogix profile container to its destination.

    .DESCRIPTION
        Handles VHD/VHDX conversion (fixed → dynamic, VHD → VHDX) and copying for one
        profile folder. Designed to be called from both sequential and concurrent (runspace)
        contexts. All file transfers use Copy-Item directly — no Robocopy dependency.

    .PARAMETER Container
        PSCustomObject describing the profile: FolderName, VHDName, VHDPath, VHDSize,
        IsDynamic, VhdFormat (as returned by Get-FSLogixContainers).

    .PARAMETER SourceUNCPath
        UNC path to the source share (e.g. \\server\profiles).

    .PARAMETER DestUNCPath
        UNC path to the destination share (e.g. \\newserver\profiles).

    .PARAMETER Rename
        When $true, renames the folder from SID_username to username_SID format.

    .PARAMETER TempPath
        Local directory for temporary VHD conversion files.

    .PARAMETER OutputType
        'VHD' or 'VHDX' — the desired output container format.

    .PARAMETER SameLocation
        $true when source and destination are the same UNC path (in-place conversion).

    .PARAMETER ForceConversion
        $true to force conversion even if the disk is already dynamic and the correct format.

    .OUTPUTS
        Hashtable with keys: Success, SourceFolder, DestFolder, SourceVHD, DestOutput,
        OriginalSize, ConvertedSize, Skipped, Error.
    #>
    param(
        [PSCustomObject]$Container,
        [string]$SourceUNCPath,
        [string]$DestUNCPath,
        [bool]$Rename,
        [string]$TempPath,
        [string]$OutputType,
        [bool]$SameLocation,
        [bool]$ForceConversion
    )

    $containerTempPath = $null

    try {
        Write-Log "[$($Container.FolderName)] Starting migration"

        # Resolve destination folder name (optionally rename SID_user → user_SID)
        $destFolderName = if ($Rename) { Convert-FolderName $Container.FolderName } else { $Container.FolderName }

        $sourceFolderPath = Join-Path $SourceUNCPath $Container.FolderName
        $destFolderPath   = Join-Path $DestUNCPath   $destFolderName
        Write-Verbose "[$($Container.FolderName)] Source folder : $sourceFolderPath"
        Write-Verbose "[$($Container.FolderName)] Dest folder   : $destFolderPath"

        if (!(Test-Path $destFolderPath)) {
            New-Item -Path $destFolderPath -ItemType Directory -Force | Out-Null
            Write-Log "[$($Container.FolderName)] Created destination folder: $destFolderPath"
        }

        $sourceVHDPath  = Join-Path $sourceFolderPath $Container.VHDName
        $outputExtension = if ($OutputType -eq 'VHDX') { '.vhdx' } else { '.vhd' }
        $outputFileName  = [System.IO.Path]::ChangeExtension($Container.VHDName, $outputExtension)
        $destVHDPath     = Join-Path $destFolderPath $outputFileName
        Write-Verbose "[$($Container.FolderName)] Source VHD : $sourceVHDPath ($([math]::Round($Container.VHDSize / 1MB, 1)) MB)"
        Write-Verbose "[$($Container.FolderName)] Dest VHD   : $destVHDPath"
        Write-Debug   "[$($Container.FolderName)] IsDynamic=$($Container.IsDynamic)  VhdFormat=$($Container.VhdFormat)  OutputType=$OutputType  SameLocation=$SameLocation  ForceConversion=$ForceConversion"

        # Decide whether conversion is needed
        $needsConversion  = $false
        $conversionReason = ''

        if ($ForceConversion) {
            $needsConversion  = $true
            $conversionReason = 'Force parameter specified'
        }
        elseif (!$Container.IsDynamic) {
            $needsConversion  = $true
            $conversionReason = 'Source is fixed disk'
        }
        elseif ($Container.VhdFormat -ne $OutputType) {
            $needsConversion  = $true
            $conversionReason = "Format conversion ($($Container.VhdFormat) -> $OutputType)"
        }
        elseif ($SameLocation) {
            # Already dynamic + correct format + same location → nothing to do
            Write-Log "[$($Container.FolderName)] Skipping - already dynamic $($Container.VhdFormat) at destination" -Level SUCCESS
            return [PSCustomObject]@{
                Success       = $true
                SourceFolder  = $Container.FolderName
                DestFolder    = $destFolderName
                SourceVHD     = $Container.VHDName
                DestOutput    = $Container.VHDName
                OriginalSize  = $Container.VHDSize
                ConvertedSize = $Container.VHDSize
                Skipped       = $true
                Error         = $null
            }
        }

        $convertedSize = $null

        if ($needsConversion) {
            Write-Log "[$($Container.FolderName)] Conversion needed: $conversionReason"

            # Use a unique temp subfolder so concurrent jobs never collide
            $containerTempPath = Join-Path $TempPath "$($Container.FolderName)_$(Get-Random)"
            New-Item -Path $containerTempPath -ItemType Directory -Force | Out-Null

            $tempVHDPath    = Join-Path $containerTempPath $Container.VHDName
            $tempOutputPath = Join-Path $containerTempPath $outputFileName
            Write-Debug "[$($Container.FolderName)] Temp VHD    : $tempVHDPath"
            Write-Debug "[$($Container.FolderName)] Temp output : $tempOutputPath"

            Write-Log "[$($Container.FolderName)] Copying VHD to temp for conversion..."
            Copy-Item -Path $sourceVHDPath -Destination $tempVHDPath -Force

            Write-Log "[$($Container.FolderName)] Converting to dynamic $OutputType..."
            Convert-VHD -Path $tempVHDPath -DestinationPath $tempOutputPath -VHDType Dynamic -DeleteSource -ErrorAction Stop

            $convertedSize    = (Get-Item $tempOutputPath).Length
            $convertedSizeGB  = [math]::Round($convertedSize / 1GB, 2)
            Write-Log "[$($Container.FolderName)] Conversion complete ($convertedSizeGB GB). Copying to destination..." -Level SUCCESS
            Write-Verbose "[$($Container.FolderName)] Size: $([math]::Round($Container.VHDSize / 1MB, 1)) MB (original) -> $([math]::Round($convertedSize / 1MB, 1)) MB (converted)"

            Copy-Item -Path $tempOutputPath -Destination $destVHDPath -Force
            Remove-Item -Path $containerTempPath -Recurse -Force -ErrorAction SilentlyContinue
            $containerTempPath = $null
        }
        else {
            # Already dynamic + correct format — direct copy, no temp needed
            Write-Log "[$($Container.FolderName)] Already dynamic $($Container.VhdFormat) - copying directly"
            Copy-Item -Path $sourceVHDPath -Destination $destVHDPath -Force
            $convertedSize = $Container.VHDSize
        }

        Write-Log "[$($Container.FolderName)] Migration completed successfully" -Level SUCCESS

        # Set ACLs inline — runs in parallel inside each job rather than serially after all jobs finish
        $userSID = Get-SIDFromFolderName -FolderName $destFolderName
        if ($userSID) {
            Set-ProfileACL -ProfilePath $destFolderPath -VHDXPath $destVHDPath -UserSID $userSID | Out-Null
        }
        else {
            Write-Log "[$($Container.FolderName)] Could not extract SID from folder name - ACLs not set" -Level WARNING
        }

        return [PSCustomObject]@{
            Success       = $true
            SourceFolder  = $Container.FolderName
            DestFolder    = $destFolderName
            SourceVHD     = $Container.VHDName
            DestOutput    = $outputFileName
            OriginalSize  = $Container.VHDSize
            ConvertedSize = $convertedSize
            Skipped       = $false
            Error         = $null
        }
    }
    catch {
        Write-Log "[$($Container.FolderName)] Migration failed: $_" -Level ERROR

        if ($containerTempPath -and (Test-Path $containerTempPath)) {
            Remove-Item -Path $containerTempPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        return [PSCustomObject]@{
            Success       = $false
            SourceFolder  = $Container.FolderName
            DestFolder    = $null
            SourceVHD     = $Container.VHDName
            DestOutput    = $null
            OriginalSize  = $Container.VHDSize
            ConvertedSize = $null
            Skipped       = $false
            Error         = $_.Exception.Message
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Set-LogFilePath',
    'Write-Log',
    'Get-AvailableDriveLetter',
    'Convert-FolderName',
    'Get-SIDFromFolderName',
    'Test-HyperVModule',
    'Set-ShareRootACL',
    'Set-ProfileACL',
    'Migrate-FSLogixContainer',
    'Connect-UNCPath',
    'Disconnect-UNCPath'
)
