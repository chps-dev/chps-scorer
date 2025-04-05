# CHPs Scorer

This tool implements automated checks for the [CHPs specification](https://github.com/chps-dev/chps).

## Installation

1. Clone the repository:
```bash
git clone https://github.com/chps-dev/chps-scorer.git
cd chps-scorer
```

## Dependencies

You will need the following software installed for full functionality. The scripts have been tested
on MacOS, let me know of any issues running in Linux.

- bash
- Docker
- jq (for JSON processing)
- curl (for API requests)
- [cosign](https://github.com/sigstore/cosign) (for signature verification)
- [grype](https://github.com/anchore/grype) (optional, for CVE scanning)
- [trufflehog](https://github.com/trufflesecurity/trufflehog) (for secret scanning)

## Where's the Container?

Yes, this should be packaged in a container so you don't have to deal with all the
dependencies. And then it can grade itself! I'm working on it...

## Usage

Basic usage:
```bash
./chps-scorer.sh [options] <image>
```

Options:
- `-o json`: Output results in JSON format
- `--skip-cves`: Skip CVE scanning
- `-d <dockerfile>`: Provide a Dockerfile for additional checks

Example:
```bash
# Basic scoring
./chps-scorer.sh nginx:latest

# JSON output with CVE scanning disabled
./chps-scorer.sh -o json --skip-cves nginx:latest

# With Dockerfile for additional checks
./chps-scorer.sh -d Dockerfile myapp:latest
```

## Scoring System

The total maximum score is 20 points, broken down as follows:

- Minimalism: 4 points
- Provenance: 8 points
- Configuration: 4 points
- CVEs: 4 points

Grades are assigned based on the percentage of points achieved.

## Output

The tool provides both human-readable and JSON output formats. The JSON output includes:
- Individual scores for each category
- Detailed check results
- Overall score and grade
- Badge URLs for visual representation

Example JSON output:
```json
{
    "image": "nginx:latest",
    "digest": "nginx@sha256:...",
    "scores": {
        "minimalism": {
            "score": 1,
            "max": 4,
            "grade": "D",
            "checks": {
                "minimal_base": "fail",
                "build_tooling": "pass",
                "shell": "fail",
                "package_manager": "fail"
            }
        },
        ...
    },
    "overall": {
        "score": 10,
        "max": 20,
        "percentage": 50,
        "grade": "C"
    }
}
```


