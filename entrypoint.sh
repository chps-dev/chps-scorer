#!/usr/bin/env bash

# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

/usr/bin/dockerd-entrypoint.sh >/dev/null 2>/dev/null &

# Wait for Docker daemon to be ready (max 10 seconds)
timeout=10
while ! docker info >/dev/null 2>&1; do
    if [ $timeout -le 0 ]; then
        echo "Error: Docker daemon failed to start within 10 seconds"
        exit 1
    fi
    sleep 1
    timeout=$((timeout - 1))
done

/chps-scorer.sh "$@"
