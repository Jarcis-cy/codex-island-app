#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_PATH="${1:-$ROOT_DIR/build/heuristic-quality.json}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

cd "$ROOT_DIR"

npm exec --yes --package=eff-u-code -- \
    fuck-u-code analyze . \
    --format json \
    --output "$OUTPUT_PATH" \
    --locale zh

echo "Heuristic quality report written to: $OUTPUT_PATH"
