#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
check_file=$(mktemp /tmp/worshipflow-transpose.XXXXXX.swift)
trap 'rm -f "$check_file"' EXIT
cat Sources/WorshipFlow/ChordLines.swift Tests/transpose-checks.swift > "$check_file"
swift -module-cache-path /tmp/worshipflow-modules "$check_file"
