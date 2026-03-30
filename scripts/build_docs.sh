#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR_INPUT="${1:-}"
DOCS_OUTPUT_DIR_INPUT="${2:-}"
CACHE_DIR_INPUT="${3:-$ROOT_DIR/.cache/hammerspoon-docs}"
HAMMERSPOON_DOCS_REF="${HAMMERSPOON_DOCS_REF:-08e93f679bb5d9b88d2e8bd493d964a133c89960}"

if [ -z "$TARGET_DIR_INPUT" ] || [ -z "$DOCS_OUTPUT_DIR_INPUT" ]; then
  echo "usage: scripts/build_docs.sh <spoon_dir> <docs_output_dir> [cache_dir]" >&2
  exit 1
fi

case "$TARGET_DIR_INPUT" in
  /*)
    TARGET_DIR="$TARGET_DIR_INPUT"
    ;;
  *)
    TARGET_DIR="$ROOT_DIR/$TARGET_DIR_INPUT"
    ;;
esac

case "$DOCS_OUTPUT_DIR_INPUT" in
  /*)
    DOCS_OUTPUT_DIR="$DOCS_OUTPUT_DIR_INPUT"
    ;;
  *)
    DOCS_OUTPUT_DIR="$ROOT_DIR/$DOCS_OUTPUT_DIR_INPUT"
    ;;
esac

case "$CACHE_DIR_INPUT" in
  /*)
    CACHE_DIR="$CACHE_DIR_INPUT"
    ;;
  *)
    CACHE_DIR="$ROOT_DIR/$CACHE_DIR_INPUT"
    ;;
esac

if [ ! -d "$TARGET_DIR" ]; then
  echo "spoon directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

HAMMERSPOON_DIR="$CACHE_DIR/hammerspoon"
VENV_DIR="$CACHE_DIR/venv"
BUILD_OUTPUT_DIR="$CACHE_DIR/build-output"

mkdir -p "$CACHE_DIR"

if [ ! -d "$HAMMERSPOON_DIR/.git" ]; then
  git clone --depth 1 https://github.com/Hammerspoon/hammerspoon "$HAMMERSPOON_DIR"
fi

git -C "$HAMMERSPOON_DIR" fetch --depth 1 origin "$HAMMERSPOON_DOCS_REF"
git -C "$HAMMERSPOON_DIR" checkout --force FETCH_HEAD

if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV_DIR/bin/python" -m pip install -r "$HAMMERSPOON_DIR/requirements.txt" >/dev/null

rm -rf "$BUILD_OUTPUT_DIR" "$DOCS_OUTPUT_DIR" "$TARGET_DIR/docs.json"
mkdir -p "$BUILD_OUTPUT_DIR" "$DOCS_OUTPUT_DIR"

(
  cd "$TARGET_DIR"
  "$VENV_DIR/bin/python" \
    "$HAMMERSPOON_DIR/scripts/docs/bin/build_docs.py" \
    --templates "$HAMMERSPOON_DIR/scripts/docs/templates/" \
    --output_dir "$BUILD_OUTPUT_DIR" \
    --json --markdown --standalone .
)

if [ ! -f "$BUILD_OUTPUT_DIR/docs.json" ]; then
  echo "docs.json was not generated" >&2
  exit 1
fi

cp "$BUILD_OUTPUT_DIR/docs.json" "$TARGET_DIR/docs.json"

if [ -f "$BUILD_OUTPUT_DIR/docs_index.json" ]; then
  cp "$BUILD_OUTPUT_DIR/docs_index.json" "$TARGET_DIR/docs_index.json"
fi

if compgen -G "$BUILD_OUTPUT_DIR/markdown/*.md" >/dev/null; then
  cp "$BUILD_OUTPUT_DIR"/markdown/*.md "$DOCS_OUTPUT_DIR/"
fi

printf 'created %s\n' "$TARGET_DIR/docs.json"
printf 'created %s\n' "$DOCS_OUTPUT_DIR"
