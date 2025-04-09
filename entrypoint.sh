#!/usr/bin/env bash

# Copyright 2025 The CHPs-dev Authors
# SPDX-License-Identifier: Apache-2.0

/usr/bin/dockerd-entrypoint.sh &
sleep 5 
/chps-scorer.sh "$@"
