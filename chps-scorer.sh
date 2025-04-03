#!/bin/bash

# CHPs Scorer - Container Hardening Priorities Scoring Tool
# This script evaluates Docker images against the CHPs criteria

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to calculate grade based on score
get_grade() {

    # Played with these grades as many vectors only have 4 max points
    local score=$1
    local max_score=$2
    local percentage=$((score * 100 / max_score))
    
    if [ $score -eq 0 ]; then
        echo "E"
    elif [ $score -eq $max_score ]; then
        echo "A+"
    elif [ $percentage -ge 75 ]; then
        echo "A"
    elif [ $percentage -ge 50 ]; then
        echo "B"
    elif [ $percentage -ge 40 ]; then
        echo "C"
    else
        echo "D"
    fi
}

# Source the check modules
source "$(dirname "$0")/minimalism_checks.sh"
source "$(dirname "$0")/provenance_checks.sh"
source "$(dirname "$0")/config_checks.sh"
source "$(dirname "$0")/cve_checks.sh"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Parse command line arguments
SKIP_CVES=false
DOCKERFILE=""
OUTPUT_FORMAT="text"
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-cves)
            SKIP_CVES=true
            shift
            ;;
        --dockerfile)
            DOCKERFILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Check if image name is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 [--skip-cves] [--dockerfile <path>] [-o|--output <format>] <docker-image-name>" >&2
    echo "Output formats: text (default), json" >&2
    exit 1
fi

# Function to generate badge URL
get_badge_url() {
    local label=$1
    local grade=$2
    local label_color="%233443F4"  # Blue label background
    local color

    # Set color based on grade
    case $grade in
        "A+") color="%2301A178";; # Green
        "A")  color="%2304B45F";; # Light green
        "B")  color="%23FFB000";; # Yellow
        "C")  color="%23FF8C00";; # Orange
        "D")  color="%23FF4400";; # Light red
        "E")  color="%23FF0000";; # Red
        *)    color="%23808080";; # Gray for unknown
    esac

    # URL encode the grade (replace + with %2B)
    local encoded_grade=${grade//+/%2B}
    
    echo "https://img.shields.io/badge/${label}-${encoded_grade}-gold?style=flat-square&labelColor=${label_color}&color=${color}"
}

# Function to check if curl exists
check_curl() {
    if ! command -v curl &> /dev/null; then
        echo "curl is required for image display but not found" >&2
        return 1
    fi
    return 0
}

# Function to detect terminal image support
detect_term_img_support() {
    # Check for iTerm2
    if [[ -n "$ITERM_SESSION_ID" ]]; then
        if [[ -n "$TERM_PROGRAM_VERSION" ]]; then
            echo "iterm"
            return 0
        fi
    fi
    
    # Check for Kitty
    if [[ -n "$KITTY_WINDOW_ID" ]]; then
        echo "kitty"
        return 0
    fi

    # Check for terminals that support sixel
    if [[ "$TERM" =~ "xterm" ]] && command -v img2sixel &> /dev/null; then
        echo "sixel"
        return 0
    fi

    echo "none"
    return 1
}

# Function to display image in terminal
display_badge() {
    local url="$1"
    local term_type="$2"
    local tmp_file="/tmp/chps-badge-$RANDOM.png"

    # Download the badge
    if ! curl -s "$url" -o "$tmp_file"; then
        echo "Failed to download badge" >&2
        return 1
    fi

    case "$term_type" in
        "iterm")
            printf '\033]1337;File=inline=1;width=auto;height=auto:'
            base64 < "$tmp_file"
            printf '\a\n'
            ;;
        "kitty")
            kitty +kitten icat "$tmp_file"
            ;;
        "sixel")
            img2sixel "$tmp_file"
            ;;
    esac

    rm -f "$tmp_file"
}

# Function to output scores in JSON format
output_json() {
    local image=$1
    local digest=$2
    local minimalism_score=$3
    local provenance_score=$4
    local config_score=$5
    local cve_score=$6
    local total_score=$7
    local max_score=$8
    local percentage=$9
    local grade=${10}
    local minimalism_json=${11}
    local provenance_json=${12}
    local config_json=${13}
    local cve_json=${14}
    
    # Calculate individual section grades
    local minimalism_grade=$(get_grade "$minimalism_score" 4)
    local provenance_grade=$(get_grade "$provenance_score" 8)
    local config_grade=$(get_grade "$config_score" 4)
    local cve_grade=$(get_grade "$cve_score" 4)

    # Generate badge URLs
    local overall_badge=$(get_badge_url "overall" "$grade")
    local minimalism_badge=$(get_badge_url "minimalism" "$minimalism_grade")
    local provenance_badge=$(get_badge_url "provenance" "$provenance_grade")
    local config_badge=$(get_badge_url "configuration" "$config_grade")
    local cve_badge=$(get_badge_url "cves" "$cve_grade")
    
    cat << EOF
{
    "image": "$image",
    "digest": "$digest",
    "scores": {
        "minimalism": {
            "score": $minimalism_score,
            "max": 4,
            "grade": "$minimalism_grade",
            "badge": "$minimalism_badge",
            "checks": $(echo "$minimalism_json" | jq '.checks')
        },
        "provenance": {
            "score": $provenance_score,
            "max": 8,
            "grade": "$provenance_grade",
            "badge": "$provenance_badge",
            "checks": $(echo "$provenance_json" | jq '.checks')
        },
        "configuration": {
            "score": $config_score,
            "max": 4,
            "grade": "$config_grade",
            "badge": "$config_badge",
            "checks": $(echo "$config_json" | jq '.checks')
        },
        "cves": {
            "score": $cve_score,
            "max": 5,
            "grade": "$cve_grade",
            "badge": "$cve_badge",
            "checks": $(echo "$cve_json" | jq '.checks')
        }
    },
    "overall": {
        "score": $total_score,
        "max": $max_score,
        "percentage": $percentage,
        "grade": "$grade",
        "badge": "$overall_badge"
    }
}
EOF
}

# Function to output scores in text format
output_text() {
    local image=$1
    local digest=$2
    local minimalism_score=$3
    local provenance_score=$4
    local config_score=$5
    local cve_score=$6
    local total_score=$7
    local max_score=$8
    local percentage=$9
    local grade=${10}
    
    # Calculate individual section grades
    local minimalism_grade=$(get_grade "$minimalism_score" 4)
    local provenance_grade=$(get_grade "$provenance_score" 8)
    local config_grade=$(get_grade "$config_score" 4)
    local cve_grade=$(get_grade "$cve_score" 4)

    # Generate badge URLs
    local overall_badge=$(get_badge_url "overall" "$grade")
    local minimalism_badge=$(get_badge_url "minimalism" "$minimalism_grade")
    local provenance_badge=$(get_badge_url "provenance" "$provenance_grade")
    local config_badge=$(get_badge_url "configuration" "$config_grade")
    local cve_badge=$(get_badge_url "cves" "$cve_grade")

    # Check for terminal image support
    local term_support
    term_support=$(detect_term_img_support)
    local can_show_images=false
    
    if [[ "$term_support" != "none" ]] && check_curl; then
        can_show_images=true
    fi
    
    echo "Scoring image: $image"
    echo "Image digest: $digest"
    echo

    echo "Minimalism Score: $minimalism_score/4 ($minimalism_grade)"
    if [[ "$can_show_images" == "true" ]]; then
        display_badge "$minimalism_badge" "$term_support"
    else
        echo "![Minimalism Badge]($minimalism_badge)"
    fi
    echo

    echo "Provenance Score: $provenance_score/8 ($provenance_grade)"
    if [[ "$can_show_images" == "true" ]]; then
        display_badge "$provenance_badge" "$term_support"
    else
        echo "![Provenance Badge]($provenance_badge)"
    fi
    echo

    echo "Configuration Score: $config_score/4 ($config_grade)"
    if [[ "$can_show_images" == "true" ]]; then
        display_badge "$config_badge" "$term_support"
    else
        echo "![Configuration Badge]($config_badge)"
    fi
    echo

    echo "CVE Score: $cve_score/4 ($cve_grade)"
    if [[ "$can_show_images" == "true" ]]; then
        display_badge "$cve_badge" "$term_support"
    else
        echo "![CVE Badge]($cve_badge)"
    fi
    echo

    echo "Overall Score: $total_score/$max_score ($percentage%)"
    echo "Grade: $grade"
    if [[ "$can_show_images" == "true" ]]; then
        display_badge "$overall_badge" "$term_support"
    else
        echo "![Overall Badge]($overall_badge)"
    fi
    echo

    if [[ "$can_show_images" == "false" ]]; then
        echo "Note: Badge URLs are formatted in Markdown. To view badges:"
        echo "1. Copy the output to a Markdown file, or"
        echo "2. Visit the URLs directly in a web browser"
        echo
        echo "To enable terminal image display, install one of the following:"
        echo "- iTerm2 terminal"
        echo "- Kitty terminal"
        echo "- A terminal with Sixel support and img2sixel"
        echo "And ensure curl is installed."
    fi
}

# Main scoring function
score_image() {
    local image=$1
    local dockerfile=$2
    
    echo "Scoring image: $image" >&2
    if [ -n "$dockerfile" ]; then
        echo "Using Dockerfile: $dockerfile" >&2
    fi
    echo "----------------------------------------" >&2
    
    # Run minimalism checks
    minimalism_json=$(run_minimalism_checks "$image" "$dockerfile")
    minimalism_score=$(echo "$minimalism_json" | jq -r '.score')

    # Run provenance checks
    provenance_json=$(run_provenance_checks "$image" "$dockerfile")
    provenance_score=$(echo "$provenance_json" | jq -r '.score')

    # Run configuration checks
    config_json=$(run_config_checks "$image" "$dockerfile")
    config_score=$(echo "$config_json" | jq -r '.score')

    # Run CVE checks
    if [ "$SKIP_CVES" != "true" ]; then
        cve_json=$(run_cve_checks "$image")
        cve_score=$(echo "$cve_json" | jq -r '.score')
    else
        cve_score=0
        cve_json='{"score": 0, "checks": {}}'
    fi

    # Calculate overall score
    local total_score=$((minimalism_score + config_score + provenance_score + cve_score))
    local max_score=20  # Updated max score (4 + 4 + 8 + 4)
    local percentage=$((total_score * 100 / max_score))
    
    # Determine grade based on percentage
    local grade
    if [ $percentage -ge 94 ]; then  # 17-18 points 
        grade="A+"
    elif [ $percentage -ge 75 ]; then  # 14-16 points 
        grade="A"
    elif [ $percentage -ge 56 ]; then  # 11-13 points 
        grade="B"
    elif [ $percentage -ge 38 ]; then  # 8-10 points 
        grade="C"
    elif [ $percentage -ge 19 ]; then  # 5-7 points 
        grade="D"
    else  # 0-4 points (Level None)
        grade="E"
    fi

    case "$OUTPUT_FORMAT" in
        json)
            output_json "$ORIGINAL_IMAGE" "$image" "$minimalism_score" "$provenance_score" "$config_score" "$cve_score" "$total_score" "$max_score" "$percentage" "$grade" "$minimalism_json" "$provenance_json" "$config_json" "$cve_json"
            ;;
        text)
            output_text "$ORIGINAL_IMAGE" "$image" "$minimalism_score" "$provenance_score" "$config_score" "$cve_score" "$total_score" "$max_score" "$percentage" "$grade"
            ;;
        *)
            echo "Error: Unknown output format '$OUTPUT_FORMAT'" >&2
            echo "Supported formats: text (default), json" >&2
            exit 1
            ;;
    esac
}

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running" >&2
    exit 1
fi

# Check if Dockerfile exists if provided
if [ -n "$DOCKERFILE" ] && [ ! -f "$DOCKERFILE" ]; then
    echo "Error: Dockerfile not found at $DOCKERFILE" >&2
    exit 1
fi

echo "Pulling image: $1" >&2

if ! docker pull "$1" > /dev/null 2>&1; then
    echo "Error: Failed to pull image" >&2
    exit 1
fi

ORIGINAL_IMAGE="$1"

# Get the full image name with digest
IMAGE_WITH_DIGEST=$(docker inspect "$1" --format '{{.RepoDigests}}' 2>/dev/null | tr -d '[]' | cut -d' ' -f1)
if [ -z "$IMAGE_WITH_DIGEST" ]; then
    echo "Warning: Could not get image digest, using original image name" >&2
    IMAGE_WITH_DIGEST="$1"
fi

# Run the scoring with the full image name including digest
score_image "$IMAGE_WITH_DIGEST" "$DOCKERFILE"