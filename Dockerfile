# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

FROM cgr.dev/chainguard/docker-dind:latest-dev@sha256:62a402422e94271e0a5d5ee55b5fe20c5aa76add2f453b74d425ceb2b7774e3c

LABEL org.opencontainers.image.source="https://github.com/chps-dev/chps-scorer"

RUN apk add trufflehog jq curl cosign grype crane
COPY *.sh .

ENTRYPOINT ["/entrypoint.sh"]
