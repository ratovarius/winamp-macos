#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

"$ROOT_DIR/scripts/generate-fixtures.sh"

ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported macOS architecture for tests: $ARCH" >&2
        exit 1
        ;;
esac

xcodebuild test \
    -project Winamp.xcodeproj \
    -scheme Winamp \
    -destination "platform=macOS,arch=${ARCH}" \
    ONLY_ACTIVE_ARCH=YES
