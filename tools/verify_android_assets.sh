#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_BASE="https://github.com/nnn308964-cpu/arch-terminal-source/releases/download/arch-rootfs-v010"

failures=0

check_proot() {
  local abi="$1"
  local path="$ROOT_DIR/android/app/src/main/assets/bin/$abi/proot"
  if [[ ! -f "$path" ]]; then
    printf 'MISSING PRoot  %-13s %s\n' "$abi" "$path"
    failures=$((failures + 1))
    return
  fi
  [[ -x "$path" ]] || {
    printf 'INVALID PRoot  %-13s not executable\n' "$abi"
    failures=$((failures + 1))
    return
  }
  printf 'OK      PRoot  %-13s sha256=%s\n' "$abi" "$(sha256sum "$path" | awk '{print $1}')"
}

check_release_asset() {
  local abi="$1"
  local file_name="$2"
  local expected_sha="$3"
  local url="$RELEASE_BASE/$file_name"
  if ! curl --fail --location --silent --show-error --range 0-1023 --output /dev/null "$url"; then
    printf 'MISSING RootFS %-13s %s\n' "$abi" "$url"
    failures=$((failures + 1))
    return
  fi
  printf 'OK      RootFS %-13s release=%s sha256=%s\n' "$abi" "$file_name" "$expected_sha"
}

check_proot arm64-v8a
check_proot armeabi-v7a
check_release_asset arm64-v8a arch-aarch64.tar 42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319
check_release_asset armeabi-v7a arch-armv7.tar ebe0fa119dea45e3af0aa61785676bdbf417bc5f754d529b87255dbf0ca4e3f0

if (( failures > 0 )); then
  printf '\n%d asset checks failed.\n' "$failures" >&2
  exit 1
fi
printf '\nUniversal APK assets and public RootFS links verified.\n'
