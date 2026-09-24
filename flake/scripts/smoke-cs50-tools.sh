#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: %s STYLE50 SOURCE_FILE JSON_VALIDATOR\n' "$0" >&2
  exit 2
fi

style50=$1
source_file=$2
json_validator=$3

export HOME="$TMPDIR"
check50 --help > /dev/null
submit50 --help > /dev/null
style50 --version > /dev/null

cp "$source_file" hello.c
"$style50" -o json hello.c > style-results.json
python "$json_validator" style-results.json
test -s style-results.json

touch "$out"
