#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  printf 'usage: %s SOURCE_FILE REPLACEMENT_FILE\n' "${0##*/}" >&2
  exit 2
fi

source_file=$1
replacement_file=$2

validate_regular_readable_file() {
  local label=$1
  local path=$2

  if [[ ! -f "$path" || ! -r "$path" ]]; then
    printf '%s: %s must be a regular readable file: %s\n' \
      "${0##*/}" "$label" "$path" >&2
    exit 2
  fi
}

validate_regular_readable_file source "$source_file"
validate_regular_readable_file replacement "$replacement_file"

if [[ ! -s "$replacement_file" ]]; then
  printf '%s: replacement file is empty: %s\n' \
    "${0##*/}" "$replacement_file" >&2
  exit 2
fi

source_dir=${source_file%/*}
if [[ "$source_dir" == "$source_file" ]]; then
  source_dir=.
elif [[ -z "$source_dir" ]]; then
  source_dir=/
fi
source_name=${source_file##*/}

if ! source_mode=$(stat -c '%a' -- "$source_file"); then
  printf '%s: failed to read source mode for %s\n' \
    "${0##*/}" "$source_file" >&2
  exit 1
fi

staging_files=()
staging_file=

cleanup_staging_files() {
  local exit_status=$?
  local cleanup_status=0
  local path

  trap - EXIT
  for path in "${staging_files[@]}"; do
    if ! rm -f -- "$path"; then
      printf '%s: failed to remove staging file: %s\n' \
        "${0##*/}" "$path" >&2
      cleanup_status=1
    fi
  done

  if (( cleanup_status != 0 )); then
    return "$cleanup_status"
  fi
  return "$exit_status"
}

create_staging_file() {
  if ! staging_file=$(mktemp --tmpdir="$source_dir" \
    ".${source_name}.staging.XXXXXX"); then
    printf '%s: failed to create staging file in source directory: %s\n' \
      "${0##*/}" "$source_dir" >&2
    return 1
  fi
  staging_files+=("$staging_file")
}

trap cleanup_staging_files EXIT

create_staging_file
first_stage=$staging_file

if ! awk \
  -v source_file="$source_file" \
  -v replacement_file="$replacement_file" '
  function fail(message) {
    if (!failed) {
      printf "patch-check50-uv.sh: first stage failed for %s: %s\n", \
        source_file, message > "/dev/stderr"
    }
    failed = 1
    exit 1
  }

  {
    if ($0 ~ /^def install_dependencies\(dependencies\):$/) {
      dependency_count++
      if (dependency_count > 1) {
        fail("install_dependencies marker appears more than once at line " \
          NR ": " $0)
      }
      if (translation_count > 0) {
        fail("install_dependencies marker appears after install_translations " \
          "at line " NR ": " $0)
      }

      in_dependency_function = 1
      replacement_status = getline replacement_line < replacement_file
      while (replacement_status > 0) {
        print replacement_line
        if (replacement_line ~ /[^[:space:]]/) {
          replacement_has_content = 1
        }
        replacement_status = getline replacement_line < replacement_file
      }
      close(replacement_file)
      if (replacement_status < 0) {
        fail("could not read replacement file " replacement_file)
      }
      if (!replacement_has_content) {
        fail("replacement file " replacement_file " contains no code")
      }
      next
    }

    if ($0 ~ /^def install_translations\(config\):$/) {
      translation_count++
      if (translation_count > 1) {
        fail("install_translations marker appears more than once at line " \
          NR ": " $0)
      }
      if (dependency_count == 0) {
        fail("install_translations marker appears before " \
          "install_dependencies at line " NR ": " $0)
      }
      in_dependency_function = 0
    }
    if (in_dependency_function &&
        $0 !~ /^[[:space:]]*$/ &&
        $0 !~ /^[[:space:]]/) {
      fail("unexpected top-level content before install_translations at line " \
        NR ": " $0)
    }


    if (!in_dependency_function) {
      print
    }
  }

  END {
    if (failed) {
      exit 1
    }
    if (dependency_count != 1) {
      printf "patch-check50-uv.sh: first stage failed for %s: expected " \
        "exactly one install_dependencies marker, found %d\n", \
        source_file, dependency_count > "/dev/stderr"
      failed = 1
    }
    if (translation_count != 1) {
      printf "patch-check50-uv.sh: first stage failed for %s: expected " \
        "exactly one install_translations marker, found %d\n", \
        source_file, translation_count > "/dev/stderr"
      failed = 1
    }
    if (!replacement_has_content) {
      printf "patch-check50-uv.sh: first stage failed for %s: replacement " \
        "file %s contains no code\n", source_file, replacement_file > "/dev/stderr"
      failed = 1
    }
    if (failed) {
      exit 1
    }
  }
' "$source_file" > "$first_stage"; then
  printf '%s: first staging pass did not complete for %s\n' \
    "${0##*/}" "$source_file" >&2
  exit 1
fi

create_staging_file
second_stage=$staging_file

if ! awk \
  -v source_file="$source_file" '
  BEGIN {
    expected_warning = "termcolor.cprint(f\"A newer version of " \
      "{package_name} is available. Run pip3 install --upgrade " \
      "{package_name} to upgrade.\", \"magenta\")"
  }

  {
    normalized = $0
    sub(/^[[:space:]]*/, "", normalized)
    if (normalized == expected_warning) {
      warning_count++
      if (warning_count > 1) {
        printf "patch-check50-uv.sh: second stage failed for %s: warning " \
          "matched more than once at line %d: %s\n", \
          source_file, NR, $0 > "/dev/stderr"
        failed = 1
        exit 1
      }

      indentation = substr($0, 1, length($0) - length(normalized))
      print indentation "termcolor.cprint(f\"A newer version of " \
        "{package_name} is available. Update the Nix-managed package.\", " \
        "\"magenta\")"
      next
    }
    print
  }

  END {
    if (failed) {
      exit 1
    }
    if (warning_count != 1) {
      printf "patch-check50-uv.sh: second stage failed for %s: expected " \
        "exactly one warning match, found %d\n", \
        source_file, warning_count > "/dev/stderr"
      exit 1
    }
  }
' "$first_stage" > "$second_stage"; then
  printf '%s: second staging pass did not complete for %s\n' \
    "${0##*/}" "$source_file" >&2
  exit 1
fi

if ! chmod -- "$source_mode" "$second_stage"; then
  printf '%s: failed to preserve mode %s on staging file for %s\n' \
    "${0##*/}" "$source_mode" "$source_file" >&2
  exit 1
fi

if ! mv -f -- "$second_stage" "$source_file"; then
  printf '%s: failed to replace source file: %s\n' \
    "${0##*/}" "$source_file" >&2
  exit 1
fi
