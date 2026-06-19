#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        echo "Install with: brew install $2" >&2
        exit 1
    fi
}

require_cmd swiftformat swiftformat
require_cmd swiftlint swiftlint

PATHS=(Sources Tests)

echo "==> SwiftFormat (lint)"
swiftformat "${PATHS[@]}" --lint

echo "==> SwiftLint"
swiftlint lint
