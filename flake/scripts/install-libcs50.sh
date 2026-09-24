#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: %s OUT VERSION SONAME_MAJOR\n' "$0" >&2
  exit 2
fi

out=$1
version=$2
soname_major=$3

mkdir -p "$out/include" "$out/lib" "$out/src" "$out/share/man/man3"
cp -a build/include/. "$out/include/"
cp -a build/lib/. "$out/lib/"
cp -a build/src/. "$out/src/"
ln -sfn "libcs50.so.${version}" "$out/lib/libcs50.so.${soname_major}"

shopt -s nullglob
for man in docs/*.3.gz; do
  install -Dm 644 "$man" "$out/share/man/man3/${man##*/}"
done
shopt -u nullglob
