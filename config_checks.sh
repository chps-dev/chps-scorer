#!/usr/bin/env bash

# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

# Function to check if user is root
check_root_user() {
    local image=$1
    local user=$(docker inspect "$image" --format '{{.Config.User}}' 2>/dev/null)
    if [ -z "$user" ] || [ "$user" = "root" ]; then
        return 0  # root user
    else
        return 1  # non-root user
    fi
}

# Function to check for files with elevated privileges
check_elevated_privileges() {
    local image=$1
    # Check for SUID/SGID files
    # First check if find command exists
    if ! docker run --rm --entrypoint which "$image" find >/dev/null 2>&1; then
        echo "Warning: 'find' command not available in image - cannot check for elevated privileges" >&2
        return 0
    fi

    if docker run --rm --user root --entrypoint find "$image" / -type f -perm /6000 2>/dev/null | grep -q .; then
        return 1
    fi
    return 0
}

# Function to check for secrets in image using Trufflehog
check_secrets() {
    local image=$1
    local dockerfile=$2
    local found_secrets=0

    if ! crane manifest --platform linux/amd64 $image > /dev/null 2>&1; then
        echo "Skipping trufflehog secret check as no linux/amd64 image was found" >&2
        return 0
    else 
        echo "Checking for secrets using Trufflehog..." >&2
    fi


    # First try using local Trufflehog if available
    if command -v trufflehog >/dev/null 2>&1; then
        echo "Using local Trufflehog installation..." >&2

        # Check Docker image
        if trufflehog docker --detector-timeout=20s --image "$image" --only-verified 2>/dev/null | grep -q "Found"; then
            found_secrets=1
            echo -e "${RED}✗ Trufflehog found verified secrets in the image${NC}" >&2
        fi

        # Check Dockerfile if provided
        if [ -n "$dockerfile" ] && [ -f "$dockerfile" ]; then
            if trufflehog filesystem --directory="$(dirname "$(realpath "$dockerfile")")" --only-verified 2>/dev/null | grep -q "Found"; then
                found_secrets=1
                echo -e "${RED}✗ Trufflehog found verified secrets in the Dockerfile${NC}" >&2
            fi
        fi

        if [ $found_secrets -eq 1 ]; then
            return 1
        fi
        return 0
    fi

    # Fall back to Docker version if local Trufflehog not available
    echo "Local Trufflehog not found, using Docker version..." >&2

    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo "Neither local Trufflehog nor Docker is available. Cannot run secret scanning." >&2
        return 1
    fi

    # Pull the Trufflehog Docker image
    if ! docker pull trufflesecurity/trufflehog:latest >/dev/null 2>&1; then
        echo "Failed to pull Trufflehog Docker image. Skipping secret scanning." >&2
        return 1
    fi

    # Run Trufflehog directly against the Docker image
    if docker run --rm \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        trufflesecurity/trufflehog:latest \
        docker --image "$image" --only-verified 2>/dev/null | grep -q "Found"; then
        found_secrets=1
        echo -e "${RED}✗ Trufflehog found verified secrets in the image${NC}" >&2
    fi

    # Also check Dockerfile if provided
    if [ -n "$dockerfile" ] && [ -f "$dockerfile" ]; then
        if docker run --rm -v "$(dirname "$(realpath "$dockerfile")"):/data" \
            trufflesecurity/trufflehog:latest \
            filesystem --directory=/data --only-verified 2>/dev/null | grep -q "Found"; then
            found_secrets=1
            echo -e "${RED}✗ Trufflehog found verified secrets in the Dockerfile${NC}" >&2
        fi
    fi

    if [ $found_secrets -eq 1 ]; then
        return 1
    fi

    return 0
}

# Function to check for annotations
check_annotations() {
    local image=$1
    # Check for org.opencontainers.image annotations
    if docker inspect "$image" | jq '.[].Config.Labels | with_entries(select(.key | startswith("org.opencontainers.image")))' >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Function to run all configuration checks
run_config_checks() {
    local image=$1
    local dockerfile=$2
    local config_score=0
    local results=()

    echo -e "\nChecking Configuration criteria..." >&2

    if check_secrets "$image" "$dockerfile"; then
        echo -e "${GREEN}✓ No obvious secrets found in image metadata or Dockerfile (Level 1)${NC}" >&2
        ((config_score++))
        results+=("secrets:pass")
    else
        echo -e "${RED}✗ Secrets found${NC}" >&2
        results+=("secrets:fail")
    fi

    if check_elevated_privileges "$image"; then
        echo -e "${GREEN}✓ No files with elevated privileges (Level 2)${NC}" >&2
        ((config_score++))
        results+=("elevated_privileges:pass")
    else
        echo -e "${RED}✗ Files with elevated privileges found${NC}" >&2
        results+=("elevated_privileges:fail")
    fi

    if ! check_root_user "$image"; then
        echo -e "${GREEN}✓ Non-root user (Level 2)${NC}" >&2
        ((config_score++))
        results+=("root_user:pass")
    else
        echo -e "${RED}✗ Running as root${NC}" >&2
        results+=("root_user:fail")
    fi

    echo -e "${YELLOW}✓ Not practical to check for file mounts for secret (Level 3)${NC}" >&2
    results+=("file_mounts:skip")

    if check_annotations "$image"; then
        echo -e "${GREEN}✓ Annotations found (Level 3)${NC}" >&2
        ((config_score++))
        results+=("annotations:pass")
    else
        echo -e "${RED}✗ No annotations found${NC}" >&2
        results+=("annotations:fail")
    fi

    echo -e "${YELLOW}✓ Not practical to check for security profiles (Level 5)${NC}" >&2
    results+=("security_profiles:skip")

    # Output JSON
    echo "{"
    echo "  \"score\": $config_score,"
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