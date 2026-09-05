# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

FROM cgr.dev/chainguard/docker-dind:latest-dev@sha256:e8b2cd3cd66cf7e64807e4e51f2739bbcd274434a406a2508a1d7ed87448b038

LABEL org.opencontainers.image.source="https://github.com/chps-dev/chps-scorer"

RUN apk add trufflehog jq curl cosign grype crane
COPY *.sh .

ENTRYPOINT ["/entrypoint.sh"]
