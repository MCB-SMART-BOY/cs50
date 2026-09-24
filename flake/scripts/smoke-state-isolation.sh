#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s SETUP_STATE_SCRIPT\n' "$0" >&2
  exit 2
fi

setup_state_script=$1
smoke_root="$TMPDIR/cs50-state-isolation"
project_root="$smoke_root/project"
mkdir -p "$project_root"
printf '%s\n' '{ description = "cs50 state isolation smoke"; }' > "$project_root/flake.nix"
cp "$setup_state_script" "$project_root/setup-state.sh"

(
  cd "$project_root"
  export CS50_PROJECT_ROOT="$smoke_root/stale"
  export CS50_STATE_DIR="$smoke_root/stale/.cs50"
  export CS50_SESSION_DIR="$smoke_root/stale/session"
  source ./setup-state.sh

  test "$CS50_PROJECT_ROOT" = "$project_root"
  test "$CS50_STATE_DIR" = "$project_root/.cs50"
  test "$HOME" = "$CS50_STATE_DIR/home"
  case "$CS50_SESSION_DIR" in
    "$CS50_STATE_DIR"/tmp/session.*) ;;
    *)
      echo "CS50_SESSION_DIR is not a project-local session" >&2
      exit 1
      ;;
  esac
  test "$TMPDIR" = "$CS50_SESSION_DIR"
  test -d "$CS50_SESSION_DIR"
  printf '%s\n' "$CS50_SESSION_DIR" > "$smoke_root/session-path"
)

session_dir=$(cat "$smoke_root/session-path")
test ! -e "$session_dir"

symlink_root="$smoke_root/symlink-project"
external_root="$smoke_root/external-target"
mkdir -p "$symlink_root" "$external_root"
printf '%s\n' '{ description = "cs50 symlink rejection smoke"; }' > "$symlink_root/flake.nix"
ln -s "$external_root" "$symlink_root/.cs50"

if (
  cd "$symlink_root"
  source "$project_root/setup-state.sh"
); then
  echo "setup-state.sh accepted a pre-existing .cs50 symlink" >&2
  exit 1
fi
test -z "$(find "$external_root" -mindepth 1 -maxdepth 1 -print -quit)"

touch "$out"
