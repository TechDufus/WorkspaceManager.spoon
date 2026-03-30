#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_INIT_LUA="$ROOT_DIR/init.lua"

usage() {
  cat <<'EOF' >&2
Usage:
  scripts/version.sh current [init_lua_path]
  scripts/version.sh next <patch|minor|major> [init_lua_path]
  scripts/version.sh set <version> [init_lua_path]
EOF
  exit 1
}

assert_semver() {
  local version="$1"

  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "invalid semver: $version" >&2
    exit 1
  fi
}

read_version() {
  local file_path="$1"
  local version

  version="$(sed -nE "s/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*\\.)?version = '([0-9]+\.[0-9]+\.[0-9]+)'.*/\2/p" "$file_path")"

  if [ -z "$version" ]; then
    echo "unable to read version from $file_path" >&2
    exit 1
  fi

  assert_semver "$version"
  printf '%s\n' "$version"
}

bump_version() {
  local version="$1"
  local part="$2"
  local major minor patch

  IFS='.' read -r major minor patch <<<"$version"

  case "$part" in
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    *)
      echo "unknown bump part: $part" >&2
      exit 1
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

write_version() {
  local version="$1"
  local file_path="$2"
  local updated_version

  assert_semver "$version"

  TARGET_VERSION="$version" perl -0pi -e \
    's/^(\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)?version = \x27)\d+\.\d+\.\d+(\x27,?\s*)$/${1}$ENV{TARGET_VERSION}${2}/m' \
    "$file_path"

  updated_version="$(read_version "$file_path")" || exit 1

  if [ "$updated_version" != "$version" ]; then
    echo "failed to update version in $file_path" >&2
    exit 1
  fi
}

command="${1:-}"

case "$command" in
  current)
    current_version="$(read_version "${2:-$DEFAULT_INIT_LUA}")" || exit 1
    printf '%s\n' "$current_version"
    ;;
  next)
    [ $# -ge 2 ] || usage
    current_version="$(read_version "${3:-$DEFAULT_INIT_LUA}")" || exit 1
    bump_version "$current_version" "$2"
    ;;
  set)
    [ $# -ge 2 ] || usage
    write_version "$2" "${3:-$DEFAULT_INIT_LUA}"
    ;;
  *)
    usage
    ;;
esac
