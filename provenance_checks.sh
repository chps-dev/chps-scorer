#!/bin/bash

# Function to check if image is signed
check_image_is_signed() {
    local image=$1
    local has_signature=0

    # Check for Cosign signatures
    if command_exists cosign; then
        # Note we don't care who signed the image, we just want to know if it is signed
        if cosign verify --certificate-identity-regexp=".*" --certificate-oidc-issuer-regexp=".*" "$image" >/dev/null 2>&1; then
            has_signature=1
        fi
    fi

    # Check for Docker Content Trust signatures
    if [ $has_signature -eq 0 ]; then
        if docker trust inspect "$image" >/dev/null 2>&1; then
            has_signature=1
        fi
    fi

    if [ $has_signature -eq 1 ]; then
        return 0
    else
        echo "No signatures found (neither Cosign nor Docker Content Trust)" >&2
        return 1
    fi
}

# Function to check for SBOM
check_sbom() {
    local image=$1
    local has_sbom=0

    # Check for Cosign SBOM attestations
    if command_exists cosign; then
        # Check for SPDX and CycloneDX SBOM attestations
        if cosign verify-attestation \
            --type spdx \
            --certificate-identity-regexp=".*" \
            --certificate-oidc-issuer-regexp=".*" \
            "$image" >/dev/null 2>&1; then
            has_sbom=1
        elif cosign verify-attestation \
            --type spdxjson \
            --certificate-identity-regexp=".*" \
            --certificate-oidc-issuer-regexp=".*" \
            "$image" >/dev/null 2>&1; then
            has_sbom=1
        elif cosign verify-attestation \
            --type cyclonedx \
            --certificate-identity-regexp=".*" \
            --certificate-oidc-issuer-regexp=".*" \
            "$image" >/dev/null 2>&1; then
            has_sbom=1
        fi
    fi

    if [ $has_sbom -eq 0 ]; then
        if [ "$(docker buildx imagetools inspect --format '{{ json .SBOM.SPDX }}' "$image")" != "null" ]; then
            has_sbom=1
            # if it's a multi-arch image, let's assume there is a linux/amd64 SBOM
        elif [ "$(docker buildx imagetools inspect --format '{{ json (index .SBOM "linux/amd64").SPDX }}' "$image")" != "null" ]; then
            has_sbom=1
        fi
    fi
    if [ $has_sbom -eq 1 ]; then
        return 0
    else
        echo "No SBOM attestations found (checked for SPDX and CycloneDX formats)" >&2
        return 1
    fi
}

# Function to check for pinned images
check_pinned_images() {
    local image=$1
    local dockerfile=$2
    
    # If Dockerfile is provided, check FROM statements in it
    if [ -n "$dockerfile" ]; then
        local unpinned_refs=$(grep -i "^FROM" "$dockerfile" | grep -v '@sha256:')
        
        if [ -n "$unpinned_refs" ]; then
            echo "Found unpinned image references in Dockerfile:" >&2
            echo "$unpinned_refs" | while read -r line; do
                echo -e "${RED}✗ $line${NC}" >&2
            done
            return 1
        fi
        return 0

    else
        echo -e "${YELLOW}No Dockerfile provided, skipping pinned image check${NC}" >&2
        return 0
    fi
    
}

# Function to check for pinned packages
check_pinned_packages() {
    local image=$1
    local dockerfile=$2

    if [ -z "$dockerfile" ]; then
        echo -e "${YELLOW}No Dockerfile provided, skipping package pinning check${NC}" >&2
        return 0
    fi

    local has_unpinned=0
    local unpinned_packages=""

    # Read the Dockerfile and check for package installations
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [ -z "$line" ] && continue

        # Check apt-get install without version pins
        if echo "$line" | grep -E 'apt-get.*install' >/dev/null; then
            if ! echo "$line" | grep -E '[=><][0-9]' >/dev/null; then
                has_unpinned=1
                unpinned_packages+="✗ Found unpinned apt packages: $line\n"
            fi
        fi

        # Check apk add without version pins
        if echo "$line" | grep -E 'apk add' >/dev/null; then
            if ! echo "$line" | grep -E '=[0-9]' >/dev/null; then
                has_unpinned=1
                unpinned_packages+="✗ Found unpinned apk packages: $line\n"
            fi
        fi

        # Check pip install without version pins
        if echo "$line" | grep -E 'pip.*install' >/dev/null; then
            if ! echo "$line" | grep -E '[=><][0-9]' >/dev/null; then
                has_unpinned=1
                unpinned_packages+="✗ Found unpinned pip packages: $line\n"
            fi
        fi

        # Check npm install without version pins
        if echo "$line" | grep -E 'npm.*install' >/dev/null; then
            if ! echo "$line" | grep -E '@[0-9]' >/dev/null; then
                has_unpinned=1
                unpinned_packages+="✗ Found unpinned npm packages: $line\n"
            fi
        fi

        # Check gem install without version pins
        if echo "$line" | grep -E 'gem.*install' >/dev/null; then
            if ! echo "$line" | grep -E ':[0-9]|-v' >/dev/null; then
                has_unpinned=1
                unpinned_packages+="✗ Found unpinned gem packages: $line\n"
            fi
        fi
    done < "$dockerfile"

    if [ $has_unpinned -eq 1 ]; then
        echo -e "${RED}Found unpinned package installations:${NC}" >&2
        echo -e "$unpinned_packages" >&2
        return 1
    fi

    return 0
}

# Function to check for provenance attestations
check_attestations() {
    local image=$1
    local has_attestations=0

    # Check for Cosign attestations
    if command_exists cosign; then
        # Check for SLSA provenance attestations with specific predicate type 
        if cosign verify-attestation \
            --type slsaprovenance1 \
            --certificate-identity-regexp=".*" \
            --certificate-oidc-issuer-regexp=".*" \
            "$image" >/dev/null 2>&1; then
            has_attestations=1
        elif cosign verify-attestation \
            --type slsaprovenance \
            --certificate-identity-regexp=".*" \
            --certificate-oidc-issuer-regexp=".*" \
            "$image" >/dev/null 2>&1; then
            has_attestations=1
        elif cosign verify-attestation \
            --type slsaprovenance02 \
            --certificate-identity-regexp=".*" \
            --certificate-oidc-issuer-regexp=".*" \
            "$image" >/dev/null 2>&1; then
            has_attestations=1
        fi
    fi

    if [ $has_attestations -eq 0 ]; then
        if [ "$(docker buildx imagetools inspect --format '{{ json .Provenance.SLSA }}' "$image")" != "null" ]; then
            has_attestations=1
            # if it's a multi-arch image, let's assume there is linux/amd64 
        elif [ "$(docker buildx imagetools inspect --format '{{ json (index .Provenance "linux/amd64").SLSA }}' "$image")" != "null" ]; then
            has_attestations=1
        fi
    fi

    if [ $has_attestations -eq 1 ]; then
        return 0
    else
        echo "No SLSA provenance attestations found" >&2
        return 1
    fi
}

# Function to check for download verification
check_download_verification() {
    local image=$1
    local dockerfile=$2
    
    # If Dockerfile is provided, check it
    if [ -n "$dockerfile" ]; then
        local has_downloads=0
        local has_verification=0
        
        # Read the Dockerfile and check for downloads and verification
        while IFS= read -r line; do
            if echo "$line" | grep -iE 'wget|curl' >/dev/null; then
                has_downloads=1
            fi
            if echo "$line" | grep -iE 'gpg|md5sum|sha256sum|sha512sum' >/dev/null; then
                has_verification=1
            fi
        done < "$dockerfile"
        
        # If we found downloads in Dockerfile, check for verification
        if [ $has_downloads -eq 1 ]; then
            if [ $has_verification -eq 1 ]; then
                return 0
            else
                echo "Found download commands but no verification commands in Dockerfile" >&2
                return 1
            fi
        fi
        # If no downloads found in Dockerfile, that's good
        return 0
    fi
    
    # Fall back to checking docker history if no Dockerfile 
    local history=$(docker history --no-trunc "$image" --format '{{.CreatedBy}}')
    
    # First check if there are any downloads at all
    if ! echo "$history" | grep -iE 'wget|curl' >/dev/null; then
        return 0  # No downloads found, so verification is not needed
    fi
    
    # If we found downloads, check for any verification commands
    if echo "$history" | grep -iE 'gpg|md5sum|sha256sum|sha512sum' >/dev/null; then
        return 0  # Found verification commands
    fi
    
    # We found downloads but no verification
    echo "Found download commands but no verification commands in image history" >&2
    return 1
}

# Function to check for trusted source
check_trusted_source() {
    local image=$1
    local dockerfile=$2

    # If we have a Dockerfile, check the FROMs
    if [ -z "$dockerfile" ]; then
        return 0
    else
        echo -e "Checking FROMs in Dockerfile" >&2
    fi

    # Get all FROM statements
    local from_images=$(grep -i "^FROM" "$dockerfile" | awk '{print $2}')

    # Check each FROM statement
    while IFS= read -r base_image; do
        # Skip empty lines
        [ -z "$base_image" ] && continue

        # Check if base image has a domain name (contains a dot) or is from a user repository
        # Extract everything before first slash (or full string if no slash)
        local prefix=${base_image%%/*}
        
        if [[ "$prefix" =~ \. ]]; then
            # Has domain name before slash, consider trusted
            return 0
        elif [[ "$base_image" =~ / ]]; then
            # No domain but has slash - likely user repo
            echo "Base image $base_image appears to be from a user repository" >&2
            return 1
        else
            # Official Docker Hub image
            return 0
        fi
    done <<< "$from_images"

    return 0
}

# Function to check if image was built in the last 30 days
check_recent_build() {
    local image_sha=$1
    local image=$ORIGINAL_IMAGE
    local current_time=$(date +%s)
    local thirty_days_ago=$((current_time - 2592000))  # 30 days in seconds
    
    # If this is a Docker Hub image, check the push date
    if [[ "$image" != *"."* || "$image" == "docker.io/"*  ]]; then
        #echo "Have docker hub image" >&2
        
        # Remove docker.io/ and library/ from the image name
        local repo_tag="${image#docker.io/}"
        repo_tag="${repo_tag#library/}"
        
        # Handle images without tags (default to 'latest')
        if [[ "$repo_tag" != *":"* ]]; then
            repo_tag="${repo_tag}:latest"
        fi
        
        local repo="${repo_tag%:*}"
        local tag="${repo_tag##*:}"
        
        # Handle official images (library/...)
        if [[ ! "$repo" =~ "/" ]]; then
            repo="library/$repo"
        fi
        
        #echo "Checking last updated date for Docker Hub image: $repo:$tag" >&2
        
        # Query Docker Hub API for last updated date
        local auth_token
        local last_updated
        
            # Get tags list and extract last updated date for our tag
            last_updated=$(curl -s "https://hub.docker.com/v2/repositories/$repo/tags/$tag" | jq -r '.last_updated')
            echo "Last updated date: $last_updated" >&2
            if [ -n "$last_updated" ]; then
                # Convert last updated date to timestamp
                local update_timestamp
                
                # Try GNU date (Linux)
                if date --version >/dev/null 2>&1; then
                    update_timestamp=$(date -d "$last_updated" +%s 2>/dev/null)
                else
                    # Try BSD date (macOS)
                    # First standardize the format
                    last_updated=$(echo "$last_updated" | sed -E 's/([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+Z/\1 \2/')
                    update_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_updated" +%s 2>/dev/null)
                fi

                echo "timestamp: $update_timestamp" >&2
                
                if [ -n "$update_timestamp" ] && [ "$update_timestamp" -gt 0 ]; then
                    if [ "$update_timestamp" -ge "$thirty_days_ago" ]; then
                        local days_old=$(( (current_time - update_timestamp) / 86400 ))
                        echo "Image tag was last updated $days_old days ago (within last 30 days)" >&2
                        return 0  # Image was updated less than 30 days ago
                    else
                        local days_old=$(( (current_time - update_timestamp) / 86400 ))
                        echo "Image tag was last updated $days_old days ago" >&2
                        return 1  # Image was updated more than 30 days ago
                    fi
                fi
            fi
        
    fi
    
    # For non-Docker Hub images or if Docker Hub API fails, use creation date
    local created_date=$(docker inspect --format '{{.Created}}' "$image" 2>/dev/null)
    
    if [ -z "$created_date" ]; then
        echo "Failed to get image creation date" >&2
        return 1
    fi
    
    # Extract the date portion for safer parsing
    created_date=${created_date%%.*}
    if [[ "$created_date" == *Z ]]; then
        created_date=${created_date%Z}
    fi
    
    # Try different date parsing approaches based on OS
    local created_timestamp=0
    
    # Try GNU date (Linux)
    if date --version >/dev/null 2>&1; then
        created_timestamp=$(date -d "$created_date" +%s 2>/dev/null)
    else
        # Try BSD date (macOS)
        created_timestamp=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$created_date" +%s 2>/dev/null)
    fi
    
    if [ -z "$created_timestamp" ] || [ "$created_timestamp" -eq 0 ]; then
        echo "Unable to parse image creation date: $created_date" >&2
        return 1
    fi
    
    if [ "$created_timestamp" -ge "$thirty_days_ago" ]; then
        local days_old=$(( (current_time - created_timestamp) / 86400 ))
        echo "Image was built $days_old days ago (within last 30 days)" >&2
        return 0  # Image is less than 30 days old
    else
        local days_old=$(( (current_time - created_timestamp) / 86400 ))
        echo "Image was built $days_old days ago" >&2
        return 1  # Image is more than 30 days old
    fi
}

# Function to run all provenance checks
run_provenance_checks() {
    local image=$1
    local dockerfile=$2
    local provenance_score=0
    local results=()
    
    echo -e "\nChecking Provenance criteria..." >&2

    if check_trusted_source "$image" "$dockerfile"; then
        echo -e "${GREEN}✓ Image from trusted source (Level 1)${NC}" >&2
        ((provenance_score++))
        results+=("trusted_source:pass")
    else
        echo -e "${RED}✗ Image not from trusted source${NC}" >&2
        results+=("trusted_source:fail")
    fi

    if check_download_verification "$image" "$dockerfile"; then
        echo -e "${GREEN}✓ No unverified downloads (Level 1)${NC}" >&2
        ((provenance_score++))
        results+=("download_verification:pass")
    else
        echo -e "${RED}✗ Unverified downloads found${NC}" >&2
        results+=("download_verification:fail")
    fi

    if check_image_is_signed "$image"; then
        echo -e "${GREEN}✓ Image is signed (Level 2)${NC}" >&2
        ((provenance_score++))
        results+=("image_signed:pass")
    else
        echo -e "${RED}✗ Image is not signed${NC}" >&2
        results+=("image_signed:fail")
    fi

    if check_recent_build "$image"; then
        echo -e "${GREEN}✓ Image was built within the last 30 days (Level 2)${NC}" >&2
        ((provenance_score++))
        results+=("recent_build:pass")
    else
        echo -e "${RED}✗ Image is older than 30 days${NC}" >&2
        results+=("recent_build:fail")
    fi

    if [ -z "$dockerfile" ]; then
        # Skip Dockerfile checks but still increment score
        ((provenance_score+=2))
        results+=("pinned_images:pass")
        results+=("pinned_packages:pass")
    else
        if check_pinned_images "$dockerfile"; then
            echo -e "${GREEN}✓ Uses digests in FROM statements (Level 2)${NC}" >&2
            ((provenance_score++))
            results+=("pinned_images:pass")
        else
            echo -e "${RED}✗ Does not use digests in FROM statements${NC}" >&2
            results+=("pinned_images:fail")
        fi

        if check_pinned_packages "$dockerfile"; then
            echo -e "${GREEN}✓ Uses pinned packages (Level 2)${NC}" >&2
            ((provenance_score++))
            results+=("pinned_packages:pass")
        else
            echo -e "${RED}✗ Does not use pinned packages${NC}" >&2
            results+=("pinned_packages:fail")
        fi
    fi

    if check_attestations "$image"; then
        echo -e "${GREEN}✓ Has provenance attestations (Level 3)${NC}" >&2
        ((provenance_score++))
        results+=("attestations:pass")
    else
        echo -e "${RED}✗ No provenance attestations${NC}" >&2
        results+=("attestations:fail")
    fi

    if check_sbom "$image"; then
        echo -e "${GREEN}✓ Has SBOM (Level 3)${NC}" >&2
        ((provenance_score++))
        results+=("sbom:pass")
    else
        echo -e "${RED}✗ No SBOM${NC}" >&2
        results+=("sbom:fail")
    fi

    # Output JSON
    echo "{"
    echo "  \"score\": $provenance_score,"
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