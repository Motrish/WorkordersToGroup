#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OTOBO_HOME_PATH="${OTOBO_HOME_PATH:-/opt/otobo}"
OUTPUT_DIR="${1:-$SOURCE_DIR/dist}"

mkdir -p "$OUTPUT_DIR"
if [[ "${USE_LOCAL_PACKAGE_BUILDER:-0}" == "1" || ! -x "$OTOBO_HOME_PATH/bin/otobo.Console.pl" ]]; then
    python3 "$SOURCE_DIR/scripts/build-package-local.py" "$SOURCE_DIR/WorkordersToGroup.sopm" "$OUTPUT_DIR"
else
    cd "$OTOBO_HOME_PATH"
    bin/otobo.Console.pl Dev::Package::Build \
        --module-directory "$SOURCE_DIR" \
        "$SOURCE_DIR/WorkordersToGroup.sopm" \
        "$OUTPUT_DIR"
fi
