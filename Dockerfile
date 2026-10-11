# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

FROM cgr.dev/chainguard/docker-dind:latest-dev@sha256:b626e209a06e4158b3372386aac4d2e64dbb26f6e2b49de085b402a8d7fd1723

LABEL org.opencontainers.image.source="https://github.com/chps-dev/chps-scorer"

RUN apk add trufflehog jq curl cosign grype crane
COPY *.sh .

ENTRYPOINT ["/entrypoint.sh"]
