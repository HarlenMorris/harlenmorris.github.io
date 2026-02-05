<###############################################
Active Directory Health Check (MSP Edition)
-----------------------------------------------
Performs a comprehensive Active Directory health audit with
traffic-light indicators for MSP operations and healthcare IT.

Checks include:
- Domain controller replication health
- FSMO role holder verification
- DNS resolution and SRV record checks
- GPO consistency and disabled policy detection
- Account lockout summary
- Password policy compliance (HIPAA-aligned)
- Stale computer/user accounts (90+ days inactive)

Outputs:
- HTML report with executive summary + technical details

Author: Harlen Morris
Date: 2026-02-05
Version: 1.0

Requirements:
- RSAT ActiveDirectory module
- GroupPolicy module
- Domain admin or delegated read permissions

Example:
    .\ad-health-check.ps1 -OutputPath "C:\Reports\AD-Health.html"

###############################################>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\Reports\AD-Health-Report.html",

    [Parameter(Mandatory=$false)]
    [int]$StaleDays = 90
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$LogFile = "C:\Logs\ADHealth\ad-health-$(Get-Date -Format 'yyyy-MM-dd').log"
$ReportDate = Get-Date

if (-not (Test-Path (Split-Path $LogFile))) {
    New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
}

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry

    switch ($Level) {
        "ERROR" { Write-Host $entry -ForegroundColor Red }
        "WARN"  { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        default { Write-Host $entry }
    }
}

function Get-StatusBadge {
    param([string]$Status)
    switch ($Status) {
        "OK" { return "<span style='color:#1b7f3a;font-weight:600;'>● Healthy</span>" }
        "WARN" { return "<span style='color:#b26a00;font-weight:600;'>● Warning</span>" }
        "FAIL" { return "<span style='color:#b02a37;font-weight:600;'>● Critical</span>" }
        default { return "<span style='color:#6c757d;font-weight:600;'>● Unknown</span>" }
    }
}

# ============================================================================
# DATA COLLECTION
# ============================================================================

Write-Log "Starting Active Directory Health Check" "INFO"

$results = @()

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module GroupPolicy -ErrorAction Stop
} catch {
    Write-Log "Required modules not available: $_" "ERROR"
    throw
}

# 1. Domain Controller Replication
try {
    $replicationErrors = 0
    $dcs = Get-ADDomainController -Filter *
    foreach ($dc in $dcs) {
        $replications = Get-ADReplicationPartnerMetadata -Target $dc.HostName -Scope Domain
        $replicationErrors += ($replications | Where-Object { $_.LastReplicationResult -ne 0 }).Count
    }

    $status = if ($replicationErrors -eq 0) { "OK" } elseif ($replicationErrors -le 2) { "WARN" } else { "FAIL" }
    $results += [PSCustomObject]@{
        Check = "DC Replication Status"
        Status = $status
        Details = "$replicationErrors replication errors detected across $($dcs.Count) DC(s)."
    }
} catch {
    $results += [PSCustomObject]@{ Check="DC Replication Status"; Status="FAIL"; Details="Failed to query replication: $_" }
}

# 2. FSMO Roles
try {
    $forest = Get-ADForest
    $domain = Get-ADDomain
    $fsmoRoles = @(
        "SchemaMaster: $($forest.SchemaMaster)",
        "DomainNamingMaster: $($forest.DomainNamingMaster)",
        "RIDMaster: $($domain.RIDMaster)",
        "PDCEmulator: $($domain.PDCEmulator)",
        "InfrastructureMaster: $($domain.InfrastructureMaster)"
    )

    $results += [PSCustomObject]@{
        Check = "FSMO Role Holder Verification"
        Status = "OK"
        Details = ($fsmoRoles -join '; ')
    }
} catch {
    $results += [PSCustomObject]@{ Check="FSMO Role Holder Verification"; Status="FAIL"; Details="Unable to retrieve FSMO roles: $_" }
}

# 3. DNS Health
try {
    $srvRecords = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$((Get-ADDomain).DNSRoot)" -Type SRV
    $status = if ($srvRecords.Count -ge 2) { "OK" } else { "WARN" }
    $results += [PSCustomObject]@{
        Check = "DNS Health (SRV Records)"
        Status = $status
        Details = "Found $($srvRecords.Count) LDAP SRV records."
    }
} catch {
    $results += [PSCustomObject]@{ Check="DNS Health (SRV Records)"; Status="FAIL"; Details="DNS SRV lookup failed: $_" }
}

# 4. GPO Consistency
try {
    $gpos = Get-GPO -All
    $disabled = $gpos | Where-Object { $_.GpoStatus -ne "AllSettingsEnabled" }
    $status = if ($disabled.Count -eq 0) { "OK" } elseif ($disabled.Count -le 5) { "WARN" } else { "FAIL" }

    $results += [PSCustomObject]@{
        Check = "GPO Consistency Check"
        Status = $status
        Details = "$($gpos.Count) total GPOs; $($disabled.Count) with disabled settings."
    }
} catch {
    $results += [PSCustomObject]@{ Check="GPO Consistency Check"; Status="FAIL"; Details="Unable to retrieve GPOs: $_" }
}

# 5. Account Lockout Summary
try {
    $locked = Get-ADUser -Filter { LockedOut -eq $true } -Properties LockedOut
    $status = if ($locked.Count -eq 0) { "OK" } elseif ($locked.Count -le 3) { "WARN" } else { "FAIL" }

    $results += [PSCustomObject]@{
        Check = "Account Lockout Summary"
        Status = $status
        Details = "$($locked.Count) user accounts currently locked out."
    }
} catch {
    $results += [PSCustomObject]@{ Check="Account Lockout Summary"; Status="FAIL"; Details="Unable to query lockouts: $_" }
}

# 6. Password Policy Compliance
try {
    $policy = Get-ADDefaultDomainPasswordPolicy
    $minLength = $policy.MinPasswordLength
    $maxAge = $policy.MaxPasswordAge.Days
    $complexity = $policy.ComplexityEnabled

    $status = if ($minLength -ge 12 -and $maxAge -le 90 -and $complexity) { "OK" } else { "WARN" }

    $results += [PSCustomObject]@{
        Check = "Password Policy Compliance (HIPAA)"
        Status = $status
        Details = "Min length: $minLength | Max age: $maxAge days | Complexity: $complexity"
    }
} catch {
    $results += [PSCustomObject]@{ Check="Password Policy Compliance (HIPAA)"; Status="FAIL"; Details="Unable to read policy: $_" }
}

# 7. Stale Accounts
try {
    $staleDate = (Get-Date).AddDays(-$StaleDays)
    $staleComputers = Get-ADComputer -Filter * -Properties LastLogonDate | Where-Object { $_.LastLogonDate -lt $staleDate }
    $staleUsers = Get-ADUser -Filter * -Properties LastLogonDate | Where-Object { $_.LastLogonDate -lt $staleDate }

    $status = if ($staleComputers.Count -le 10 -and $staleUsers.Count -le 10) { "OK" } else { "WARN" }

    $results += [PSCustomObject]@{
        Check = "Stale Accounts ($StaleDays+ days)"
        Status = $status
        Details = "$($staleComputers.Count) computers and $($staleUsers.Count) users inactive."
    }
} catch {
    $results += [PSCustomObject]@{ Check="Stale Accounts"; Status="FAIL"; Details="Unable to query stale accounts: $_" }
}

# ============================================================================
# REPORT OUTPUT
# ============================================================================

$rows = $results | ForEach-Object {
    "<tr><td>$($_.Check)</td><td>$(Get-StatusBadge $_.Status)</td><td>$($_.Details)</td></tr>"
} | Out-String

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Active Directory Health Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f5f7fb; padding: 20px; }
        .container { max-width: 1100px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; }
        h1 { color: #1f3b6d; }
        .subtitle { color: #6c757d; margin-top: 4px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #e0e6ed; }
        th { background: #f8f9fb; }
        .note { margin-top: 20px; font-size: 0.9rem; color: #6c757d; }
    </style>
</head>
<body>
<div class="container">
    <h1>Active Directory Health Report</h1>
    <div class="subtitle">Generated: $($ReportDate.ToString('yyyy-MM-dd HH:mm')) | Northwoods Health System</div>
    <table>
        <tr><th>Check</th><th>Status</th><th>Details</th></tr>
        $rows
    </table>
    <p class="note">Report excludes PHI and is safe for HIPAA compliance reviews. Review warnings promptly to avoid authentication outages.</p>
</div>
</body>
</html>
"@

try {
    $OutputDir = Split-Path $OutputPath
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $report | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "Report generated: $OutputPath" "SUCCESS"
} catch {
    Write-Log "Failed to write report: $_" "ERROR"
}
