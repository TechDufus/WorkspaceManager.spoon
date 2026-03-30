#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR_INPUT="${2:-dist}"
VERSION="${1:-}"
SPOON_NAME="WorkspaceManager"
ARCHIVE_NAME="${SPOON_NAME}.spoon.zip"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"

if [ -z "$VERSION" ]; then
  echo "usage: scripts/package_spoon.sh <version> [output_dir]" >&2
  exit 1
fi

case "$OUTPUT_DIR_INPUT" in
  /*)
    OUTPUT_DIR="$OUTPUT_DIR_INPUT"
    ;;
  *)
    OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR_INPUT"
    ;;
esac

"$ROOT_DIR/scripts/version.sh" current >/dev/null

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/workspace-manager-spoon.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

STAGE_DIR="$TMP_DIR/${SPOON_NAME}.spoon"
mkdir -p "$STAGE_DIR"

for file_name in init.lua workspace_manager.lua screens.lua summon.lua LICENSE README.md; do
  cp "$ROOT_DIR/$file_name" "$STAGE_DIR/$file_name"
done

"$ROOT_DIR/scripts/version.sh" set "$VERSION" "$STAGE_DIR/init.lua" >/dev/null
"$ROOT_DIR/scripts/build_docs.sh" "$STAGE_DIR" "$STAGE_DIR/docs"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$ARCHIVE_NAME" "$OUTPUT_DIR/$CHECKSUM_NAME"

(
  cd "$TMP_DIR"
  zip -rq "$OUTPUT_DIR/$ARCHIVE_NAME" "${SPOON_NAME}.spoon"
)

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$ARCHIVE_NAME" >"$CHECKSUM_NAME"
)

printf 'created %s\n' "$OUTPUT_DIR/$ARCHIVE_NAME"
printf 'created %s\n' "$OUTPUT_DIR/$CHECKSUM_NAME"
