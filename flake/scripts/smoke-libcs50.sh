#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  printf 'usage: %s LIBCS50_PREFIX SOURCE_FILE\n' "$0" >&2
  exit 2
fi

libcs50_prefix=$1
source_file=$2

export C_INCLUDE_PATH="$libcs50_prefix/include"
export LIBRARY_PATH="$libcs50_prefix/lib"
export LD_LIBRARY_PATH="$libcs50_prefix/lib"
export CC=clang
export CFLAGS='-ggdb3 -O0 -std=c17 -Wall -Werror -Wextra -Wno-sign-compare -Wno-unused-parameter -Wshadow'
export LDLIBS='-lcs50 -lm'

cp "$source_file" hello.c
clang hello.c -lcs50 -lm -o hello-direct
test "$(printf 'World\n' | ./hello-direct)" = 'Name: hello, World'

make hello
test "$(printf 'Make\n' | ./hello)" = 'Name: hello, Make'

touch "$out"
