#!/usr/bin/env bash

# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

# Function to check for shell
check_shell() {
    local image=$1
    local shells=("/bin/sh" "/bin/bash" "/bin/ash" "/bin/zsh")
    for shell in "${shells[@]}"; do
        if check_file_exists "$image" "$shell"; then
            return 1
        fi
    done
    return 0
}

# Function to check if a file exists in the image
check_file_exists() {
    local image=$1
    local file=$2
    local container_id=$(docker create "$image")
    local result=1
    if docker cp "$container_id:$file" - >/dev/null 2>&1; then
        result=0
    fi
    docker rm "$container_id" >/dev/null 2>&1
    return $result
}

# Function to check if a package exists in the image
check_package_exists() {
    local image=$1
    local package=$2
    # Big assumption here that "which" exists
    docker run --rm --entrypoint which "$image" "$package" >/dev/null 2>&1
}

# Function to check for package managers
check_package_manager() {
    local image=$1
    local package_managers=("apt" "apk" "yum" "dnf" "pip" "npm")
    for pm in "${package_managers[@]}"; do
        if check_package_exists "$image" "$pm"; then
            return 1
        fi
    done
    return 0
}

# Function to check for build and debug tooling
check_build_tooling() {
    local image=$1
    local build_tools=("gcc" "g++" "make" "cmake" "gdb" "lldb" "strace" "ltrace" "perf" "maven" "javac" "cargo" "npm" "yarn" "pip" "pip3")
    for tool in "${build_tools[@]}"; do
        if check_package_exists "$image" "$tool"; then
            return 1
        fi
    done
    return 0
}

# Function to check for minimal base image
check_minimal_base() {
    local image=$1
    local dockerfile=$2

    # If Dockerfile is provided, check the final FROM statement (normally production build)
    if [ -n "$dockerfile" ]; then
        local base_image=$(grep -i "^FROM" "$dockerfile" | tail -n1 | awk '{print $2}')
        if [[ "$base_image" =~ ^(cgr\.dev/|alpine|slim|scratch) ]]; then
            echo "Dockerfile uses a minimal base image $base_image" >&2
            return 0
        fi
    fi

    # Fall back to size check
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
    esac
    local size_bytes=$(crane manifest --platform linux/${arch} "$image" | jq '.config.size + ([.layers[].size] | add)')

    if [ "$size_bytes" -lt 40000000 ]; then
        echo "Compressed image is $size_bytes bytes, assuming minimal base image" >&2
        return 0
    fi
    return 1
}

# Function to run all minimalism checks
run_minimalism_checks() {
    local image=$1
    local dockerfile=$2
    local minimalism_score=0
    local results=()

    echo -e "\nChecking Minimalism criteria..." >&2

    if check_minimal_base "$image" "$dockerfile"; then
        echo -e "${GREEN}✓ Using minimal base image (compressed image <40MB) (Level 1)${NC}" >&2
        ((minimalism_score++))
        results+=("minimal_base:pass")
    else
        echo -e "${RED}✗ Not using minimal base image (compressed image >40MB) (Level 1)${NC}" >&2
        results+=("minimal_base:fail")
    fi

    if check_build_tooling "$image"; then
        echo -e "${GREEN}✓ No build/debug tooling found (Level 2)${NC}" >&2
        ((minimalism_score++))
        results+=("build_tooling:pass")
    else
        echo -e "${RED}✗ Build/debug tooling found${NC}" >&2
        results+=("build_tooling:fail")
    fi

    if check_shell "$image"; then
        echo -e "${GREEN}✓ No shell found (Level 3)${NC}" >&2
        ((minimalism_score++))
        results+=("shell:pass")
    else
        echo -e "${RED}✗ Shell found${NC}" >&2
        results+=("shell:fail")
    fi

    if check_package_manager "$image"; then
        echo -e "${GREEN}✓ No package manager found (Level 3)${NC}" >&2
        ((minimalism_score++))
        results+=("package_manager:pass")
    else
        echo -e "${RED}✗ Package manager found${NC}" >&2
        results+=("package_manager:fail")
    fi

    # Output JSON
    echo "{"
    echo "  \"score\": $minimalism_score,"
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