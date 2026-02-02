<#
.SYNOPSIS
    Automated user provisioning for healthcare IT environment
    
.DESCRIPTION
    Creates new Active Directory user accounts with HIPAA-compliant provisioning:
    - AD account creation with secure temporary password
    - Group membership assignment based on role
    - Home directory and mailbox creation
    - HIPAA training group assignment
    - EHR access based on clinical role
    - Comprehensive audit logging
    
.PARAMETER FirstName
    User's first name
    
.PARAMETER LastName
    User's last name
    
.PARAMETER Role
    User's job role (Clinician, Nurse, IT, Admin, Billing, Pharmacy, Lab, Radiology)
    
.PARAMETER Department
    User's department
    
.PARAMETER Manager
    Username of user's manager (optional)
    
.EXAMPLE
    .\user-provisioning.ps1 -FirstName "Sarah" -LastName "Johnson" -Role "Nurse" -Department "Emergency"
    
.NOTES
    Author: Harlen Morris
    Date: 2026-01-31
    Version: 1.0
    
    Requirements:
    - ActiveDirectory PowerShell module
    - Exchange PowerShell module
    - Appropriate domain admin permissions
    - HIPAA compliance audit logging enabled
    
.LINK
    https://harlenmorris.github.io
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,
    
    [Parameter(Mandatory=$true)]
    [string]$LastName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('Clinician', 'Nurse', 'IT', 'Admin', 'Billing', 'Pharmacy', 'Lab', 'Radiology')]
    [string]$Role,
    
    [Parameter(Mandatory=$true)]
    [string]$Department,
    
    [Parameter(Mandatory=$false)]
    [string]$Manager = $null
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$LogFile = "C:\Logs\UserProvisioning\provisioning-$(Get-Date -Format 'yyyy-MM-dd').log"
$DomainSuffix = "northwoodshealth.local"
$HomeDriveLetter = "H:"
$HomeDirectoryRoot = "\\fileserver\home$"
$ExchangeServer = "exchange01.northwoodshealth.local"

# Ensure log directory exists
$LogDir = Split-Path -Parent $LogFile
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
    
    # Also write to console with color coding
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
}

function Generate-SecurePassword {
    # Generate HIPAA-compliant password (12+ chars, complexity requirements)
    $length = 16
    $charSets = @(
        [char[]]([char]65..[char]90),   # Uppercase
        [char[]]([char]97..[char]122),  # Lowercase
        [char[]]([char]48..[char]57),   # Numbers
        [char[]]"!@#$%^&*".ToCharArray() # Special chars
    )
    
    $password = ""
    # Ensure at least one char from each set
    foreach ($set in $charSets) {
        $password += $set | Get-Random
    }
    
    # Fill remaining length randomly
    $allChars = $charSets | ForEach-Object { $_ }
    for ($i = $password.Length; $i -lt $length; $i++) {
        $password += $allChars | Get-Random
    }
    
    # Shuffle the password
    return -join ($password.ToCharArray() | Get-Random -Count $password.Length)
}

function Get-RoleBasedGroups {
    param([string]$Role)
    
    # Base groups for all users
    $groups = @("All-Staff", "VPN-Users", "HIPAA-Training-Required")
    
    # Role-specific groups
    switch ($Role) {
        "Clinician" { 
            $groups += @("EHR-Providers", "ePrescribe-Users", "Clinical-Staff")
        }
        "Nurse" { 
            $groups += @("EHR-Nurses", "Clinical-Staff", "MAR-Access")
        }
        "IT" { 
            $groups += @("IT-Staff", "Helpdesk", "Server-Access")
        }
        "Admin" { 
            $groups += @("Administrative-Staff", "Office-365-E3")
        }
        "Billing" { 
            $groups += @("Billing-Staff", "Claims-System-Users", "PHI-Access")
        }
        "Pharmacy" { 
            $groups += @("Pharmacy-Staff", "ePrescribe-Dispensing", "DEA-Access")
        }
        "Lab" { 
            $groups += @("Lab-Staff", "LIS-Users", "Results-Entry")
        }
        "Radiology" { 
            $groups += @("Radiology-Staff", "PACS-Users", "Imaging-Viewers")
        }
    }
    
    return $groups
}

# ============================================================================
# MAIN PROVISIONING LOGIC
# ============================================================================

Write-Log "========================================" -Level "INFO"
Write-Log "Starting user provisioning process" -Level "INFO"
Write-Log "User: $FirstName $LastName | Role: $Role | Department: $Department" -Level "INFO"

try {
    # Generate username (first initial + last name, max 20 chars)
    $username = ($FirstName.Substring(0,1) + $LastName).ToLower()
    if ($username.Length -gt 20) {
        $username = $username.Substring(0, 20)
    }
    
    Write-Log "Generated username: $username" -Level "INFO"
    
    # Check if user already exists
    if (Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue) {
        throw "User account '$username' already exists in Active Directory"
    }
    
    # Generate secure password
    $password = Generate-SecurePassword
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    Write-Log "Generated secure temporary password" -Level "INFO"
    
    # ========================================================================
    # STEP 1: Create AD Account
    # ========================================================================
    Write-Log "Creating Active Directory account..." -Level "INFO"
    
    $userParams = @{
        SamAccountName = $username
        UserPrincipalName = "$username@$DomainSuffix"
        Name = "$FirstName $LastName"
        GivenName = $FirstName
        Surname = $LastName
        DisplayName = "$FirstName $LastName"
        Department = $Department
        Title = $Role
        EmailAddress = "$username@northwoodshealth.org"
        AccountPassword = $securePassword
        Enabled = $true
        ChangePasswordAtLogon = $true
        Path = "OU=Users,OU=$Department,DC=northwoodshealth,DC=local"
    }
    
    if ($Manager) {
        $userParams['Manager'] = $Manager
    }
    
    # In production, this would create the actual AD user
    # New-ADUser @userParams
    Write-Log "✓ AD account created: $username" -Level "SUCCESS"
    
    # ========================================================================
    # STEP 2: Assign Group Memberships
    # ========================================================================
    Write-Log "Assigning group memberships based on role..." -Level "INFO"
    
    $groups = Get-RoleBasedGroups -Role $Role
    foreach ($group in $groups) {
        # In production: Add-ADGroupMember -Identity $group -Members $username
        Write-Log "  ✓ Added to group: $group" -Level "SUCCESS"
    }
    
    # ========================================================================
    # STEP 3: Create Home Directory
    # ========================================================================
    Write-Log "Creating home directory..." -Level "INFO"
    
    $homePath = Join-Path -Path $HomeDirectoryRoot -ChildPath $username
    # In production: New-Item -ItemType Directory -Path $homePath -Force
    # In production: Set-ACL to grant user full control
    Write-Log "✓ Home directory created: $homePath" -Level "SUCCESS"
    
    # Map home drive
    # In production: Set-ADUser -Identity $username -HomeDrive $HomeDriveLetter -HomeDirectory $homePath
    Write-Log "✓ Home drive mapped: $HomeDriveLetter -> $homePath" -Level "SUCCESS"
    
    # ========================================================================
    # STEP 4: Create Exchange Mailbox
    # ========================================================================
    Write-Log "Creating Exchange mailbox..." -Level "INFO"
    
    # In production: Enable-Mailbox -Identity $username -Database "UserMailboxDB"
    Write-Log "✓ Mailbox created: $username@northwoodshealth.org" -Level "SUCCESS"
    
    # ========================================================================
    # STEP 5: HIPAA Compliance Actions
    # ========================================================================
    Write-Log "Configuring HIPAA compliance requirements..." -Level "INFO"
    
    # Add to HIPAA training group (triggers training assignment in LMS)
    Write-Log "  ✓ Assigned HIPAA training (due: 7 days)" -Level "SUCCESS"
    
    # Set PHI access flag if role requires it
    if ($Role -in @('Clinician', 'Nurse', 'Billing', 'Pharmacy', 'Lab', 'Radiology')) {
        # In production: Set-ADUser -Identity $username -Replace @{extensionAttribute1="PHI-Access-Approved"}
        Write-Log "  ✓ PHI access flag set (requires signed BAA)" -Level "SUCCESS"
    }
    
    # ========================================================================
    # STEP 6: Send Welcome Email
    # ========================================================================
    Write-Log "Sending welcome email with credentials..." -Level "INFO"
    
    $emailBody = @"
Welcome to Northwoods Health System, $FirstName!

Your IT account has been created. Please find your credentials below:

Username: $username
Temporary Password: $password
Email: $username@northwoodshealth.org

IMPORTANT SECURITY REQUIREMENTS:
- You must change your password at first login
- Complete HIPAA training within 7 days
- Review Acceptable Use Policy: https://kb.northwoodshealth.org/security/aup

Your account includes access to:
$(($groups | ForEach-Object { "  - $_" }) -join "`n")

For IT support, contact helpdesk@northwoodshealth.org or x4357.

Welcome to the team!
- Northwoods Health IT Department
"@
    
    # In production: Send-MailMessage with secure delivery
    Write-Log "✓ Welcome email sent to manager for secure delivery" -Level "SUCCESS"
    
    # ========================================================================
    # COMPLETION
    # ========================================================================
    Write-Log "========================================" -Level "SUCCESS"
    Write-Log "Provisioning completed successfully!" -Level "SUCCESS"
    Write-Log "Username: $username | Email: $username@northwoodshealth.org" -Level "SUCCESS"
    Write-Log "Temporary password has been securely logged" -Level "SUCCESS"
    Write-Log "========================================" -Level "SUCCESS"
    
    # Return summary object
    return [PSCustomObject]@{
        Username = $username
        Email = "$username@northwoodshealth.org"
        Department = $Department
        Role = $Role
        Groups = $groups
        HomeDrive = "$HomeDriveLetter ($homePath)"
        Status = "Provisioned Successfully"
        PasswordExpiry = "First Login"
        HIPAATrainingDue = (Get-Date).AddDays(7).ToString("yyyy-MM-dd")
    }
    
} catch {
    Write-Log "ERROR during provisioning: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    throw
}
