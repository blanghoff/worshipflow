#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
check_file=$(mktemp /tmp/worshipflow-parser.XXXXXX.swift)
trap 'rm -f "$check_file"' EXIT
sed '/@MainActor final class LyricsImportDraft/,$d' Sources/WorshipFlow/LyricsImport.swift | sed '/import SwiftUI/d' > "$check_file"
cat Tests/parser-checks.swift >> "$check_file"
swift -module-cache-path /tmp/worshipflow-modules "$check_file"
