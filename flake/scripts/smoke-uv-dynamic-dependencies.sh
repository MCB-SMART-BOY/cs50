#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  printf 'usage: %s DEPENDENCY_PATH SMOKE_SCRIPT\n' "$0" >&2
  exit 2
fi

dependency_path=$1
smoke_script=$2

export HOME="$TMPDIR"
export CS50_TEST_INHERITED_MARKER=must-not-reach-uv
export UV_CACHE_DIR="$TMPDIR/uv-cache"
export CS50_UV_DEPENDENCY="cs50-uv-dependency @ file://${dependency_path}"

python "$smoke_script"
touch "$out"
