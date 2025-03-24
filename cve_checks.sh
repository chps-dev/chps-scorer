#!/bin/bash

# Function to check for critical CVEs using Grype
check_cves() {
    local image=$1
    if [ "$SKIP_CVES" = "true" ]; then
        echo "0 0 0 0"  # Return all zeros when CVEs are skipped
        return 0
    fi

    if command_exists grype; then
        # Count vulnerabilities by severity
        local grype_output=$(grype "$image" -o table 2>/dev/null)
        local critical=$(echo "$grype_output" | grep -c "Critical")
        local high=$(echo "$grype_output" | grep -c "High")
        local medium=$(echo "$grype_output" | grep -c "Medium")
        local any=$(if echo "$grype_output" | grep -q "No vulnerabilities found"; then echo "0"; else echo "1"; fi)
        
        # Return as space-separated values
        echo "$critical $high $medium $any"
    else
        echo "Grype not installed. Skipping CVE checks." >&2
        return 1
    fi
}


# Function to run all CVE checks
run_cve_checks() {
    local image=$1
    local cve_score=0
    local results=()
    
    echo -e "\nChecking CVE criteria..." >&2
    local vulns=($(check_cves "$image"))
    
    if [ ${#vulns[@]} -eq 4 ]; then
        if [ "${vulns[0]}" -eq 0 ]; then
            echo -e "${GREEN}✓ No critical vulnerabilities (Level 2)${NC}" >&2
            ((cve_score++))
            results+=("critical_vulns:pass")
        else
            echo -e "${RED}✗ Found ${vulns[0]} critical vulnerabilities${NC}" >&2
            results+=("critical_vulns:fail")
        fi
        
        if [ "${vulns[1]}" -eq 0 ]; then
            echo -e "${GREEN}✓ No high vulnerabilities (Level 3)${NC}" >&2
            ((cve_score++))
            results+=("high_vulns:pass")
        else
            echo -e "${RED}✗ Found ${vulns[1]} high vulnerabilities${NC}" >&2
            results+=("high_vulns:fail")
        fi
        
        if [ "${vulns[2]}" -eq 0 ]; then
            echo -e "${GREEN}✓ No medium vulnerabilities (Level 4)${NC}" >&2
            ((cve_score++))
            results+=("medium_vulns:pass")
        else
            echo -e "${RED}✗ Found ${vulns[2]} medium vulnerabilities${NC}" >&2
            results+=("medium_vulns:fail")
        fi
        
        if [ "${vulns[3]}" -eq 0 ]; then
            echo -e "${GREEN}✓ No vulnerabilities found (Level 5)${NC}" >&2
            ((cve_score++))
            results+=("any_vulns:pass")
        else
            echo -e "${RED}✗ Vulnerabilities found (possibly negligible or unknown)${NC}" >&2
            results+=("any_vulns:fail")
        fi
    else
        echo -e "${YELLOW}⚠ Could not check vulnerabilities${NC}" >&2
        results+=("critical_vulns:skip")
        results+=("high_vulns:skip")
        results+=("medium_vulns:skip")
        results+=("any_vulns:skip")
    fi
    
    # Output JSON
    echo "{"
    echo "  \"score\": $cve_score,"
    echo "  \"checks\": {"
    for ((i=0; i<${#results[@]}; i++)); do
        local check=${results[$i]}
        local name=${check%%:*}
        local result=${check##*:}
        echo -n "    \"$name\": \"$result\""
        if [ $i -lt $((${#results[@]}-1)) ]; then
            echo ","
        else
            echo ""
        fi
    done
    echo "  }"
    echo "}"
} 