<###############################################
Microsoft 365 License Audit (MSP Edition)
-----------------------------------------------
Audits Microsoft 365 license utilization and produces a
cost-optimization report. Designed for MSP and healthcare
IT environments where licensing costs must be controlled
and access must follow least-privilege principles.

Checks include:
- Total vs assigned vs available per SKU
- Users with multiple license SKUs
- Disabled users still consuming licenses
- Cost estimation per SKU
- Optimization recommendations

Outputs:
- HTML report
- CSV exports for finance / BI analysis

Author: Harlen Morris
Date: 2026-02-05
Version: 1.0

Requirements:
- MSOnline PowerShell module
- Global admin or license admin permissions

Example:
    .\m365-license-audit.ps1 -OutputPath "C:\Reports\M365-License-Audit.html"

###############################################>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\Reports\M365-License-Audit.html",

    [Parameter(Mandatory=$false)]
    [string]$CsvSummaryPath = "C:\Reports\M365-License-Summary.csv",

    [Parameter(Mandatory=$false)]
    [string]$CsvUserPath = "C:\Reports\M365-License-Users.csv"
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$LogFile = "C:\Logs\M365License\m365-license-$(Get-Date -Format 'yyyy-MM-dd').log"
$ReportDate = Get-Date

$skuCosts = @{
    "ENTERPRISEPACK" = 36.00
    "STANDARDPACK"   = 12.50
    "SPE_E5"         = 57.00
    "SPE_E3"         = 36.00
    "BUSINESS_PREMIUM" = 22.00
    "EXCHANGESTANDARD" = 8.00
}

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

function Get-LicenseCost {
    param([string]$Sku)
    if ($skuCosts.ContainsKey($Sku)) { return $skuCosts[$Sku] }
    return 0
}

# ============================================================================
# DATA COLLECTION
# ============================================================================

Write-Log "Starting Microsoft 365 License Audit" "INFO"

try {
    Import-Module MSOnline -ErrorAction Stop
    Connect-MsolService -ErrorAction Stop
} catch {
    Write-Log "Failed to connect to MSOnline: $_" "ERROR"
    throw
}

try {
    $skus = Get-MsolAccountSku
    $users = Get-MsolUser -All
} catch {
    Write-Log "Failed to retrieve license data: $_" "ERROR"
    throw
}

# Summary by SKU
$skuSummary = foreach ($sku in $skus) {
    $available = $sku.ActiveUnits - $sku.ConsumedUnits
    $cost = Get-LicenseCost $sku.SkuPartNumber
    [PSCustomObject]@{
        Sku = $sku.SkuPartNumber
        Total = $sku.ActiveUnits
        Assigned = $sku.ConsumedUnits
        Available = $available
        MonthlyCost = ($sku.ConsumedUnits * $cost)
        UnitCost = $cost
    }
}

# Users with multiple licenses
$multiLicenseUsers = $users | Where-Object { $_.Licenses.Count -gt 1 }

# Disabled users still licensed
$disabledLicensedUsers = $users | Where-Object { $_.BlockCredential -eq $true -and $_.Licenses.Count -gt 0 }

# Optimization recommendations
$recommendations = @()
if ($disabledLicensedUsers.Count -gt 0) {
    $recommendations += "Reclaim $($disabledLicensedUsers.Count) licenses from disabled accounts"
}
if ($multiLicenseUsers.Count -gt 0) {
    $recommendations += "Review $($multiLicenseUsers.Count) users with multiple SKUs for redundancy"
}
if (-not $recommendations) {
    $recommendations += "License usage appears optimized based on current data"
}

# ============================================================================
# REPORT OUTPUT
# ============================================================================

$summaryRows = $skuSummary | ForEach-Object {
    "<tr><td>$($_.Sku)</td><td>$($_.Total)</td><td>$($_.Assigned)</td><td>$($_.Available)</td><td>$($_.UnitCost)</td><td>$($_.MonthlyCost)</td></tr>"
} | Out-String

$multiRows = $multiLicenseUsers | Select-Object -First 10 | ForEach-Object {
    "<tr><td>$($_.DisplayName)</td><td>$($_.UserPrincipalName)</td><td>$($_.Licenses.Count)</td></tr>"
} | Out-String

$disabledRows = $disabledLicensedUsers | Select-Object -First 10 | ForEach-Object {
    "<tr><td>$($_.DisplayName)</td><td>$($_.UserPrincipalName)</td><td>$($_.Licenses.Count)</td></tr>"
} | Out-String

$recommendationList = ($recommendations | ForEach-Object { "<li>$_</li>" }) -join ""

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Microsoft 365 License Audit</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f5f7fb; padding: 20px; }
        .container { max-width: 1100px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; }
        h1 { color: #1f3b6d; }
        h2 { color: #1f3b6d; margin-top: 25px; }
        .subtitle { color: #6c757d; margin-top: 4px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #e0e6ed; }
        th { background: #f8f9fb; }
        ul { margin-top: 10px; }
        .note { margin-top: 20px; font-size: 0.9rem; color: #6c757d; }
    </style>
</head>
<body>
<div class="container">
    <h1>Microsoft 365 License Audit</h1>
    <div class="subtitle">Generated: $($ReportDate.ToString('yyyy-MM-dd HH:mm')) | MSP Cost Optimization</div>

    <h2>License Utilization Summary</h2>
    <table>
        <tr><th>SKU</th><th>Total</th><th>Assigned</th><th>Available</th><th>Unit Cost ($)</th><th>Monthly Cost ($)</th></tr>
        $summaryRows
    </table>

    <h2>Users with Multiple Licenses (Top 10)</h2>
    <table>
        <tr><th>Name</th><th>UPN</th><th>License Count</th></tr>
        $multiRows
    </table>

    <h2>Disabled Users Still Licensed (Top 10)</h2>
    <table>
        <tr><th>Name</th><th>UPN</th><th>License Count</th></tr>
        $disabledRows
    </table>

    <h2>Optimization Recommendations</h2>
    <ul>
        $recommendationList
    </ul>

    <p class="note">Licensing reviews should align with HIPAA least-privilege controls and MFA enforcement for clinical staff.</p>
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
    $skuSummary | Export-Csv -Path $CsvSummaryPath -NoTypeInformation -Encoding UTF8
    $multiLicenseUsers | Select-Object DisplayName, UserPrincipalName, @{Name="LicenseCount";Expression={$_.Licenses.Count}} | Export-Csv -Path $CsvUserPath -NoTypeInformation -Encoding UTF8

    Write-Log "Report generated: $OutputPath" "SUCCESS"
    Write-Log "CSV summary exported: $CsvSummaryPath" "SUCCESS"
    Write-Log "CSV user export: $CsvUserPath" "SUCCESS"
} catch {
    Write-Log "Failed to write report: $_" "ERROR"
}
