#!/usr/bin/env bash

# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

/usr/bin/dockerd-entrypoint.sh >/dev/null 2>/dev/null &
sleep 2
/chps-scorer.sh "$@"
