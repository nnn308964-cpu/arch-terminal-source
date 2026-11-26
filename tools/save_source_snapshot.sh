#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_DIR="$ROOT_DIR/versions"
mkdir -p "$VERSIONS_DIR"

last_number="$(find "$VERSIONS_DIR" -maxdepth 1 -type f -name 'arch_terminal_local_project_v*.zip' -printf '%f\n' 2>/dev/null \
  | sed -n 's/^arch_terminal_local_project_v\([0-9][0-9][0-9]\)\.zip$/\1/p' \
  | sort -n | tail -n 1)"
last_number="${last_number:-0}"
next_number=$((10#$last_number + 1))
version="$(printf '%03d' "$next_number")"
archive="$VERSIONS_DIR/arch_terminal_local_project_v${version}.zip"

(
  cd "$ROOT_DIR"
  zip -qr "$archive" . \
    -x 'build/*' \
       '.dart_tool/*' \
       '.gradle/*' \
       'android/.gradle/*' \
       'linux/flutter/ephemeral/*' \
       'windows/flutter/ephemeral/*' \
       'versions/*' \

)

sha256sum "$archive" > "$archive.sha256"
printf 'saved source snapshot: %s\n' "$archive"
printf 'sha256 file: %s\n' "$archive.sha256"
