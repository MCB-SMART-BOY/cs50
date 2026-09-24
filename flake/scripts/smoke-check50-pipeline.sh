#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: %s LIBCS50_PREFIX CHECKS_DIR SOURCE_FILE\n' "$0" >&2
  exit 2
fi

libcs50_prefix=$1
checks_dir=$2
source_file=$3

export HOME="$TMPDIR"
export C_INCLUDE_PATH="$libcs50_prefix/include"
export LIBRARY_PATH="$libcs50_prefix/lib"
export LD_LIBRARY_PATH="$libcs50_prefix/lib"

mkdir student
cd student
cp "$source_file" caesar.c
check50 -d "$checks_dir" -o json > results.json

test "$(grep -c '"passed": true' results.json)" -eq 3
! grep -q '"passed": false' results.json

touch "$out"
