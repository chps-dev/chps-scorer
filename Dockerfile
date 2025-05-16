# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

FROM cgr.dev/chainguard/docker-dind:latest-dev@sha256:3ee1d42190674e34043b09428b6a36a965491214bff021634c20e5146b2e0724

LABEL org.opencontainers.image.source="https://github.com/chps-dev/chps-scorer"

RUN apk add trufflehog jq curl cosign grype crane
COPY *.sh .

ENTRYPOINT ["/entrypoint.sh"]
