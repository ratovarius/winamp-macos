#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v uv >/dev/null 2>&1; then
    echo "uv is required. Install from https://docs.astral.sh/uv/" >&2
    exit 1
fi

uv sync
uv run generate-fixtures
