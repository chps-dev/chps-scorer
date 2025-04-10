# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

FROM cgr.dev/chainguard/docker-dind:latest-dev@sha256:eac615966ff1d0c0cb9dca7933594654cb433f6d27bbb0d40602746c8eb85b42

LABEL org.opencontainers.image.source="https://github.com/chps-dev/chps-scorer"

RUN apk add trufflehog jq curl cosign grype
COPY *.sh .

ENTRYPOINT ["/entrypoint.sh"]
