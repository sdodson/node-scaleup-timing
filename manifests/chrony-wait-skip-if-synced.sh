#!/bin/bash
# Check if the chrony drift file was modified less than 60 minutes ago.
# If so, touch a flag file that chrony-wait.service can check via
# ConditionPathExists to skip blocking on NTP sync.
DRIFT=/var/lib/chrony/drift
FLAG=/run/chrony-recently-synced
if [ -f "$DRIFT" ]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$DRIFT") ))
    if [ "$AGE" -lt 3600 ]; then
        touch "$FLAG"
        exit 0
    fi
fi
