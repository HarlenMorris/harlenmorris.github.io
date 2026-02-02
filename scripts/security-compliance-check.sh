#!/bin/bash

################################################################################
# HIPAA Security Compliance Check Script
#
# Purpose: Automated security audit for HIPAA-regulated healthcare IT environments
#          Validates compliance with security controls and generates scorecard
#
# Author: Harlen Morris
# Date: 2026-01-31
# Version: 1.0
#
# Compliance Areas:
#   - Password policy enforcement
#   - Disk encryption status
#   - Antivirus definitions currency
#   - Firewall configuration
#   - USB device restrictions
#   - Unencrypted ePHI detection
#   - Remote access security
#   - Audit logging
#
# Usage:
#   ./security-compliance-check.sh [--report csv|html|json]
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed (non-critical)
#   2 - Critical security failure detected
################################################################################

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

REPORT_DIR="/var/log/security-compliance"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
REPORT_FILE="$REPORT_DIR/compliance-report-$TIMESTAMP.txt"
CSV_FILE="$REPORT_DIR/compliance-$TIMESTAMP.csv"
LOG_FILE="$REPORT_DIR/compliance-check.log"

# Compliance scoring
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
CRITICAL_FAILURES=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Report format (default: text)
REPORT_FORMAT="text"

# ============================================================================
# FUNCTIONS
# ============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

check_result() {
    local check_name="$1"
    local result="$2"
    local is_critical="${3:-false}"
    local details="${4:-}"
    
    ((TOTAL_CHECKS++))
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}[✓ PASS]${NC} $check_name"
        ((PASSED_CHECKS++))
        echo "$check_name,PASS,$details" >> "$CSV_FILE"
    elif [ "$result" = "WARN" ]; then
        echo -e "${YELLOW}[⚠ WARN]${NC} $check_name"
        echo "$check_name,WARN,$details" >> "$CSV_FILE"
    else
        echo -e "${RED}[✗ FAIL]${NC} $check_name"
        ((FAILED_CHECKS++))
        echo "$check_name,FAIL,$details" >> "$CSV_FILE"
        
        if [ "$is_critical" = "true" ]; then
            ((CRITICAL_FAILURES++))
        fi
    fi
    
    if [ -n "$details" ]; then
        echo "       Details: $details"
    fi
}

# ============================================================================
# COMPLIANCE CHECKS
# ============================================================================

check_password_policy() {
    print_header "Password Policy Compliance"
    
    # Check minimum password length
    if command -v pwscore &> /dev/null; then
        local min_length=$(grep -E "^minlen" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}')
        
        if [ -n "$min_length" ] && [ "$min_length" -ge 12 ]; then
            check_result "Minimum password length (≥12 chars)" "PASS" false "Set to $min_length"
        else
            check_result "Minimum password length (≥12 chars)" "FAIL" true "Currently $min_length (HIPAA requires ≥12)"
        fi
    else
        check_result "Password policy tools installed" "WARN" false "pwquality not found"
    fi
    
    # Check password complexity
    if grep -q "^dcredit" /etc/security/pwquality.conf 2>/dev/null; then
        check_result "Password complexity requirements" "PASS" false "Configured"
    else
        check_result "Password complexity requirements" "FAIL" true "Not enforced"
    fi
    
    # Check password aging
    local max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
    if [ -n "$max_days" ] && [ "$max_days" -le 90 ]; then
        check_result "Password expiration (≤90 days)" "PASS" false "Set to $max_days days"
    else
        check_result "Password expiration (≤90 days)" "FAIL" true "Set to $max_days days (HIPAA requires ≤90)"
    fi
}

check_disk_encryption() {
    print_header "Disk Encryption Status"
    
    # Check for LUKS encryption
    if command -v cryptsetup &> /dev/null; then
        local encrypted_volumes=$(lsblk -o NAME,TYPE,FSTYPE | grep -c "crypto_LUKS" || true)
        
        if [ "$encrypted_volumes" -gt 0 ]; then
            check_result "Full disk encryption (LUKS)" "PASS" false "$encrypted_volumes encrypted volumes detected"
        else
            check_result "Full disk encryption (LUKS)" "FAIL" true "No encrypted volumes found - ePHI at risk"
        fi
    else
        check_result "Encryption tools available" "WARN" false "cryptsetup not installed"
    fi
    
    # Check for encrypted home directories
    if [ -d "/home/.ecryptfs" ]; then
        check_result "Encrypted home directories" "PASS" false "ecryptfs detected"
    else
        check_result "Encrypted home directories" "WARN" false "Not using ecryptfs"
    fi
}

check_antivirus() {
    print_header "Antivirus Protection"
    
    # Check for ClamAV
    if command -v clamscan &> /dev/null; then
        check_result "Antivirus software installed" "PASS" false "ClamAV detected"
        
        # Check definition age
        if [ -f /var/lib/clamav/daily.cvd ]; then
            local def_age_days=$(( ( $(date +%s) - $(stat -c %Y /var/lib/clamav/daily.cvd) ) / 86400 ))
            
            if [ "$def_age_days" -le 7 ]; then
                check_result "Antivirus definitions current (≤7 days)" "PASS" false "Updated $def_age_days days ago"
            else
                check_result "Antivirus definitions current (≤7 days)" "FAIL" false "Definitions $def_age_days days old"
            fi
        fi
        
        # Check if service is running
        if systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
            check_result "Antivirus auto-update service" "PASS" false "clamav-freshclam active"
        else
            check_result "Antivirus auto-update service" "WARN" false "Service not running"
        fi
    else
        check_result "Antivirus software installed" "FAIL" true "No antivirus detected"
    fi
}

check_firewall() {
    print_header "Firewall Configuration"
    
    # Check UFW status
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            check_result "Host firewall enabled" "PASS" false "UFW active"
            
            # Check default deny policy
            if ufw status verbose | grep -q "Default: deny (incoming)"; then
                check_result "Default deny incoming" "PASS" false "Secure default policy"
            else
                check_result "Default deny incoming" "FAIL" true "Permissive default policy"
            fi
        else
            check_result "Host firewall enabled" "FAIL" true "UFW not active"
        fi
    # Check iptables as fallback
    elif command -v iptables &> /dev/null; then
        local rule_count=$(iptables -L INPUT -n | wc -l)
        if [ "$rule_count" -gt 3 ]; then
            check_result "Firewall rules configured" "PASS" false "iptables rules present"
        else
            check_result "Firewall rules configured" "FAIL" true "No iptables rules"
        fi
    else
        check_result "Firewall software" "FAIL" true "No firewall found"
    fi
    
    # Check for open RDP/VNC ports (security risk)
    local dangerous_ports=$(ss -tln | grep -E ":(3389|5900)" || true)
    if [ -z "$dangerous_ports" ]; then
        check_result "No exposed RDP/VNC ports" "PASS" false "Secure"
    else
        check_result "No exposed RDP/VNC ports" "FAIL" true "Dangerous ports open: $dangerous_ports"
    fi
}

check_usb_restrictions() {
    print_header "USB Device Controls"
    
    # Check if USB storage is blocked
    if lsmod | grep -q "usb_storage"; then
        # Module loaded - check if restricted
        if [ -f /etc/modprobe.d/blacklist-usb-storage.conf ]; then
            check_result "USB storage restrictions" "PASS" false "Blacklist configured"
        else
            check_result "USB storage restrictions" "WARN" false "USB storage not restricted (data exfiltration risk)"
        fi
    else
        check_result "USB storage module disabled" "PASS" false "usb_storage not loaded"
    fi
    
    # Check usbguard if available
    if command -v usbguard &> /dev/null; then
        if systemctl is-active --quiet usbguard 2>/dev/null; then
            check_result "USBGuard protection" "PASS" false "Active"
        else
            check_result "USBGuard protection" "WARN" false "Installed but not active"
        fi
    else
        check_result "USBGuard software" "WARN" false "Not installed"
    fi
}

check_ephi_exposure() {
    print_header "Unencrypted ePHI Detection"
    
    # Simulated check - in production would scan for common ePHI file patterns
    # Look for unencrypted database files outside encrypted volumes
    
    local unencrypted_db_paths=(
        "/var/lib/mysql"
        "/var/lib/postgresql"
        "/opt/ehr/database"
    )
    
    local violations=0
    for db_path in "${unencrypted_db_paths[@]}"; do
        if [ -d "$db_path" ]; then
            # Check if path is on encrypted volume
            local mount_point=$(df "$db_path" | tail -1 | awk '{print $6}')
            if ! mount | grep "$mount_point" | grep -q "crypt"; then
                ((violations++))
                log "WARNING: Potential unencrypted ePHI at $db_path"
            fi
        fi
    done
    
    if [ $violations -eq 0 ]; then
        check_result "No unencrypted ePHI storage" "PASS" false "Database paths encrypted"
    else
        check_result "No unencrypted ePHI storage" "FAIL" true "$violations database paths unencrypted"
    fi
}

check_audit_logging() {
    print_header "Audit Logging Configuration"
    
    # Check auditd service
    if systemctl is-active --quiet auditd 2>/dev/null; then
        check_result "Audit daemon running" "PASS" false "auditd active"
        
        # Check audit rules for HIPAA-relevant events
        if auditctl -l 2>/dev/null | grep -q "syscall"; then
            check_result "Audit rules configured" "PASS" false "Syscall auditing enabled"
        else
            check_result "Audit rules configured" "WARN" false "Limited audit coverage"
        fi
    else
        check_result "Audit daemon running" "FAIL" true "auditd not active - no compliance trail"
    fi
    
    # Check log retention
    if [ -f /etc/audit/auditd.conf ]; then
        local max_log_file=$(grep "^max_log_file " /etc/audit/auditd.conf | awk '{print $3}')
        if [ -n "$max_log_file" ] && [ "$max_log_file" -ge 10 ]; then
            check_result "Audit log retention" "PASS" false "Configured for ${max_log_file}MB"
        else
            check_result "Audit log retention" "WARN" false "Low retention limit"
        fi
    fi
}

check_remote_access() {
    print_header "Remote Access Security"
    
    # Check SSH configuration
    if [ -f /etc/ssh/sshd_config ]; then
        # Root login disabled
        if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
            check_result "SSH root login disabled" "PASS" false "Secure"
        else
            check_result "SSH root login disabled" "FAIL" true "Root login allowed"
        fi
        
        # Password authentication (should prefer keys)
        if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
            check_result "SSH key-based auth enforced" "PASS" false "Passwords disabled"
        else
            check_result "SSH key-based auth enforced" "WARN" false "Password auth allowed"
        fi
        
        # Check for VPN requirement
        local ssh_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        ssh_port=${ssh_port:-22}
        
        if ss -tln | grep -q ":$ssh_port "; then
            check_result "SSH not directly exposed" "WARN" false "SSH accessible on port $ssh_port (should require VPN)"
        fi
    fi
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_compliance_scorecard() {
    local score_percent=$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))
    
    cat > "$REPORT_FILE" <<EOF
================================================================================
HIPAA SECURITY COMPLIANCE AUDIT REPORT
================================================================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $HOSTNAME
Auditor: Security Compliance Scanner v1.0

================================================================================
COMPLIANCE SCORE
================================================================================
Total Checks:     $TOTAL_CHECKS
Passed:           $PASSED_CHECKS (${GREEN}✓${NC})
Failed:           $FAILED_CHECKS (${RED}✗${NC})
Critical Fails:   $CRITICAL_FAILURES (${RED}⚠${NC})

OVERALL SCORE:    $score_percent% $([ $score_percent -ge 90 ] && echo "(${GREEN}EXCELLENT${NC})" || [ $score_percent -ge 75 ] && echo "(${YELLOW}GOOD${NC})" || echo "(${RED}NEEDS IMPROVEMENT${NC})")

================================================================================
COMPLIANCE STATUS
================================================================================
EOF

    if [ $score_percent -ge 90 ]; then
        echo "✓ COMPLIANT - System meets HIPAA security requirements" >> "$REPORT_FILE"
    elif [ $score_percent -ge 75 ]; then
        echo "⚠ PARTIALLY COMPLIANT - Some improvements needed" >> "$REPORT_FILE"
    else
        echo "✗ NON-COMPLIANT - Significant security gaps detected" >> "$REPORT_FILE"
    fi
    
    if [ $CRITICAL_FAILURES -gt 0 ]; then
        cat >> "$REPORT_FILE" <<EOF

⚠⚠⚠ CRITICAL FINDINGS ⚠⚠⚠
$CRITICAL_FAILURES critical security failures require immediate remediation.
These failures pose significant risk to ePHI confidentiality, integrity, or availability.
EOF
    fi
    
    cat >> "$REPORT_FILE" <<EOF

================================================================================
DETAILED RESULTS
================================================================================
See CSV report: $CSV_FILE
Full log: $LOG_FILE

================================================================================
RECOMMENDATIONS
================================================================================
EOF

    if [ $FAILED_CHECKS -gt 0 ]; then
        echo "1. Review failed checks and remediate within 30 days" >> "$REPORT_FILE"
        echo "2. Document remediation actions in HIPAA compliance log" >> "$REPORT_FILE"
        echo "3. Re-run compliance check to verify fixes" >> "$REPORT_FILE"
    fi
    
    echo "4. Schedule next compliance audit: $(date -d '+1 month' '+%Y-%m-%d')" >> "$REPORT_FILE"
    echo "5. Review audit logs for unauthorized access attempts" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" <<EOF

================================================================================
Generated by: security-compliance-check.sh v1.0
Author: Harlen Morris
Contact: IT Security Team - security@northwoodshealth.org
================================================================================
EOF

    cat "$REPORT_FILE"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --report)
            REPORT_FORMAT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--report csv|html|json]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Ensure report directory exists
mkdir -p "$REPORT_DIR"

# Initialize CSV
echo "Check,Result,Details" > "$CSV_FILE"

# Run all compliance checks
print_header "HIPAA Security Compliance Check"
echo "Starting audit on $HOSTNAME at $(date)"
echo ""

check_password_policy
check_disk_encryption
check_antivirus
check_firewall
check_usb_restrictions
check_ephi_exposure
check_audit_logging
check_remote_access

# Generate final report
echo ""
generate_compliance_scorecard

# Determine exit code
if [ $CRITICAL_FAILURES -gt 0 ]; then
    log "CRITICAL: $CRITICAL_FAILURES critical failures detected"
    exit 2
elif [ $FAILED_CHECKS -gt 0 ]; then
    log "WARNING: $FAILED_CHECKS checks failed"
    exit 1
else
    log "SUCCESS: All compliance checks passed"
    exit 0
fi
