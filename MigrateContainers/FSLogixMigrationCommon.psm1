<#
.SYNOPSIS
    Common functions module for FSLogix profile container migration scripts.

.DESCRIPTION
    This module contains shared functions used by both Azure Files and Generic UNC path
    migration scripts. Functions include logging, folder naming, SID extraction, 
    ACL management, and VHD conversion utilities.

.NOTES
    File Name      : FSLogixMigrationCommon.psm1
    Author         : GitHub Copilot
    Prerequisite   : PowerShell 5.1+
    Version        : 1.0
    Date           : 2026-04-03
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

# Export functions
Export-ModuleMember -Function @(
    'Set-LogFilePath',
    'Write-Log',
    'Get-AvailableDriveLetter',
    'Convert-FolderName',
    'Get-SIDFromFolderName',
    'Test-HyperVModule',
    'Set-ShareRootACL',
    'Set-ProfileACL'
)
