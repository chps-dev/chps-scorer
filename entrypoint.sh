#!/bin/bash

/usr/bin/dockerd-entrypoint.sh >/dev/null 2>/dev/null &
sleep 2
/chps-scorer.sh $@
