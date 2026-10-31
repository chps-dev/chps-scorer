# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

FROM cgr.dev/chainguard/docker-dind:latest-dev@sha256:4622f1d48eb808c9cf5072282783308d7897110376d54918916a5135661210c6

LABEL org.opencontainers.image.source="https://github.com/chps-dev/chps-scorer"

RUN apk add trufflehog jq curl cosign grype crane
COPY *.sh .

ENTRYPOINT ["/entrypoint.sh"]
