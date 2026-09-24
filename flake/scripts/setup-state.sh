#!/usr/bin/env bash

cs50_session_dir=
cs50_previous_exit_trap=$(trap -p EXIT)

cs50_fail() {
  printf 'CS50 state setup: %s\n' "$*" >&2
  if [ -n "${cs50_session_dir:-}" ] && [ -d "$cs50_session_dir" ]; then
    if ! rm -rf -- "$cs50_session_dir"; then
      printf "CS50 state setup: clean temporary session '%s' failed\n" \
        "$cs50_session_dir" >&2
    fi
  fi
  return 1
}

cs50_ensure_directory() {
  local path=$1

  if [ -L "$path" ]; then
    cs50_fail "refusing symlink where directory is required: '$path'"
    return 1
  fi
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    cs50_fail "refusing non-directory where directory is required: '$path'"
    return 1
  fi
  if [ ! -e "$path" ] && ! (umask 077 && mkdir -m 700 -- "$path"); then
    cs50_fail "create directory '$path'"
    return 1
  fi
  if ! chmod 700 -- "$path"; then
    cs50_fail "set directory mode 0700 on '$path'"
    return 1
  fi
}

cs50_ensure_file() {
  local path=$1

  if [ -L "$path" ]; then
    cs50_fail "refusing symlink where state file is required: '$path'"
    return 1
  fi
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    cs50_fail "refusing non-regular state file: '$path'"
    return 1
  fi
  if [ ! -e "$path" ] && ! (umask 077 && : > "$path"); then
    cs50_fail "create state file '$path'"
    return 1
  fi
  if ! chmod 600 -- "$path"; then
    cs50_fail "set state file mode 0600 on '$path'"
    return 1
  fi
}

cs50_select_project_root() {
  if [ "${CS50_PROJECT_ROOT_OVERRIDE+x}" = x ]; then
    cs50_project_root_input=$CS50_PROJECT_ROOT_OVERRIDE
    cs50_project_root_source=override
  else
    # All other CS50_* values are outputs from a previous shell and never
    # select a new project root. Use the shell's current working directory.
    cs50_project_root_input=${PWD-}
    cs50_project_root_source=working-directory
  fi

  if [ -z "$cs50_project_root_input" ]; then
    cs50_fail "resolve project root: path is empty"
    return 1
  fi
  case $cs50_project_root_input in
    /*) ;;
    *)
      cs50_fail \
        "validate project root '$cs50_project_root_input': path is not absolute"
      return 1
      ;;
  esac
  if [ "$cs50_project_root_source" = working-directory ] &&
    { [ -L "$cs50_project_root_input/flake.nix" ] ||
      [ ! -f "$cs50_project_root_input/flake.nix" ]; }; then
    cs50_fail \
      "validate flake.nix '$cs50_project_root_input/flake.nix': ordinary file required in current PWD"
    return 1
  fi
}

cs50_unset_variables() {
  local variable

  for variable in "$@"; do
    if ! unset "$variable"; then
      cs50_fail "clear inherited variable '$variable'"
      return 1
    fi
  done
}

cs50_clear_inherited_state() {
  local variable
  local variables=(
    HOME TMPDIR XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
    GNUPGHOME CHECK50_PATH GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
    GIT_CONFIG_NOSYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR
    GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
    GIT_SSH_COMMAND GIT_PROXY_COMMAND GIT_ASKPASS SSH_ASKPASS
    UV_CONFIG_FILE UV_CACHE_DIR UV_TOOL_BIN_DIR UV_TOOL_DIR
    UV_PYTHON_INSTALL_DIR UV_PYTHON_BIN_DIR UV_PROJECT_ENVIRONMENT UV_PROJECT
    UV_WORKING_DIR UV_INDEX_URL UV_EXTRA_INDEX_URL UV_DEFAULT_INDEX UV_FIND_LINKS
    UV_NO_CONFIG UV_NO_CACHE PIP_CONFIG_FILE PIP_CACHE_DIR PIP_INDEX_URL
    PIP_EXTRA_INDEX_URL PIP_FIND_LINKS PYTHONPATH PYTHONHOME PYTHONUSERBASE
    VIRTUAL_ENV CS50_PROJECT_ROOT CS50_STATE_DIR CS50_SESSION_DIR
    CS50_PROJECT_ROOT_OVERRIDE
  )

  cs50_unset_variables "${variables[@]}" || return 1
  for variable in ${!GIT_CONFIG_KEY_@} ${!GIT_CONFIG_VALUE_@}; do
    cs50_unset_variables "$variable" || return 1
  done
}

cs50_install_cleanup_trap() {
  local cleanup_command
  local previous_exit_action
  local encoded_exit_action

  printf -v cleanup_command 'rm -rf -- %q' "$cs50_session_dir"
  if [[ "$cs50_previous_exit_trap" == trap\ --\ *\ EXIT ]]; then
    encoded_exit_action=${cs50_previous_exit_trap#trap -- }
    encoded_exit_action=${encoded_exit_action% EXIT}
    if [[ ${encoded_exit_action:0:1} != "'" ||
      ${encoded_exit_action: -1} != "'" ]]; then
      cs50_fail "decode the inherited EXIT trap"
      return 1
    fi
    if ! previous_exit_action=$(
      "$BASH" -c 'printf "%s" '"$encoded_exit_action"
    ); then
      cs50_fail "decode the inherited EXIT trap"
      return 1
    fi
    cleanup_command="$cleanup_command; $previous_exit_action"
  fi
  if ! trap "$cleanup_command" EXIT; then
    cs50_fail "install EXIT cleanup for temporary session '$cs50_session_dir'"
    return 1
  fi
}

if ! cs50_select_project_root; then
  return 1
fi
if ! cs50_host_home=${HOME-}; then
  cs50_fail "read host HOME before state isolation"
  return 1
fi
if ! cs50_project_root=$(cd -- "$cs50_project_root_input" 2>/dev/null && pwd -P); then
  cs50_fail "canonicalize project root '$cs50_project_root_input'"
  return 1
fi
if [ -L "$cs50_project_root" ] || [ ! -d "$cs50_project_root" ]; then
  cs50_fail "validate canonical project root '$cs50_project_root': directory required"
  return 1
fi

cs50_flake="$cs50_project_root/flake.nix"
if [ -L "$cs50_flake" ] || [ ! -f "$cs50_flake" ]; then
  cs50_fail "validate flake.nix '$cs50_flake': ordinary file required"
  return 1
fi

cs50_state_dir="$cs50_project_root/.cs50"
cs50_home="$cs50_state_dir/home"
cs50_check50_path="$cs50_state_dir/check50"
cs50_config_dir="$cs50_state_dir/config"
cs50_cache_dir="$cs50_state_dir/cache"
cs50_data_dir="$cs50_state_dir/data"
cs50_runtime_state_dir="$cs50_state_dir/state"
cs50_tmp_dir="$cs50_state_dir/tmp"
cs50_uv_cache_dir="$cs50_state_dir/uv-cache"
cs50_uv_tools_dir="$cs50_state_dir/uv-tools"
cs50_gnupg_dir="$cs50_state_dir/gnupg"

cs50_state_directories=(
  "$cs50_state_dir" "$cs50_home" "$cs50_check50_path" "$cs50_config_dir"
  "$cs50_cache_dir" "$cs50_data_dir" "$cs50_runtime_state_dir"
  "$cs50_tmp_dir" "$cs50_uv_cache_dir" "$cs50_uv_tools_dir"
  "$cs50_gnupg_dir"
)
for cs50_directory in "${cs50_state_directories[@]}"; do
  if ! cs50_ensure_directory "$cs50_directory"; then
    return 1
  fi
done

cs50_git_config="$cs50_state_dir/gitconfig"
cs50_sqlite_history="$cs50_state_dir/sqlite-history"
cs50_gdb_history="$cs50_state_dir/gdb-history"
cs50_state_files=("$cs50_git_config" "$cs50_sqlite_history" "$cs50_gdb_history")
for cs50_file in "${cs50_state_files[@]}"; do
  if ! cs50_ensure_file "$cs50_file"; then
    return 1
  fi
done

if ! cs50_session_dir=$(umask 077 && mktemp -d -- "$cs50_tmp_dir/session.XXXXXX"); then
  cs50_fail "create temporary session directory under '$cs50_tmp_dir'"
  return 1
fi
if [ -L "$cs50_session_dir" ] || [ ! -d "$cs50_session_dir" ]; then
  cs50_fail \
    "validate temporary session directory '$cs50_session_dir': directory required"
  return 1
fi
if ! chmod 700 -- "$cs50_session_dir"; then
  cs50_fail "set temporary session mode 0700 on '$cs50_session_dir'"
  return 1
fi
if ! cs50_install_cleanup_trap; then
  return 1
fi

if ! cs50_clear_inherited_state; then
  return 1
fi

cs50_path=${PATH-}
case ":$cs50_path:" in
  *:"$cs50_uv_tools_dir":*) ;;
  *) cs50_path="$cs50_uv_tools_dir${cs50_path:+:$cs50_path}" ;;
esac
cs50_git_global_config=$cs50_git_config
if [ "${CS50_PRESERVE_HOST_GIT_CONFIG:-0}" = 1 ] &&
  [ -n "$cs50_host_home" ] && [ -f "$cs50_host_home/.gitconfig" ]; then
  cs50_git_global_config=$cs50_host_home/.gitconfig
fi

if [ "${CS50_PRESERVE_HOST_SSH:-0}" = 1 ] && [ -n "$cs50_host_home" ]; then
  cs50_host_ssh_config="$cs50_host_home/.ssh/config"
  cs50_host_known_hosts="$cs50_host_home/.ssh/known_hosts"
  if [ -f "$cs50_host_ssh_config" ] || [ -f "$cs50_host_known_hosts" ]; then
    cs50_ssh_command=ssh
    if [ -f "$cs50_host_ssh_config" ]; then
      printf -v cs50_quoted_option '%q' "$cs50_host_ssh_config"
      cs50_ssh_command+=" -F $cs50_quoted_option"
    fi
    if [ -f "$cs50_host_known_hosts" ]; then
      printf -v cs50_quoted_option '%q' \
        "UserKnownHostsFile=$cs50_host_known_hosts"
      cs50_ssh_command+=" -o $cs50_quoted_option"
    fi
    export GIT_SSH_COMMAND="$cs50_ssh_command"
  fi
fi

export \
  CS50_PROJECT_ROOT="$cs50_project_root" \
  CS50_STATE_DIR="$cs50_state_dir" \
  CS50_SESSION_DIR="$cs50_session_dir" \
  HOME="$cs50_home" \
  TMPDIR="$cs50_session_dir" \
  CHECK50_PATH="$cs50_check50_path" \
  XDG_CONFIG_HOME="$cs50_config_dir" \
  XDG_CACHE_HOME="$cs50_cache_dir" \
  XDG_DATA_HOME="$cs50_data_dir" \
  XDG_STATE_HOME="$cs50_runtime_state_dir" \
  UV_CACHE_DIR="$cs50_uv_cache_dir" \
  UV_TOOL_BIN_DIR="$cs50_uv_tools_dir" \
  GNUPGHOME="$cs50_gnupg_dir" \
  SQLITE_HISTORY="$cs50_sqlite_history" \
  GDBHISTFILE="$cs50_gdb_history" \
  GIT_CONFIG_GLOBAL="$cs50_git_global_config" \
  GIT_CONFIG_NOSYSTEM=1 \
  PATH="$cs50_path" \
  PYTHONDONTWRITEBYTECODE=1

unset -f cs50_fail cs50_ensure_directory cs50_ensure_file
unset -f cs50_select_project_root cs50_unset_variables
unset -f cs50_clear_inherited_state cs50_install_cleanup_trap
unset cs50_previous_exit_trap cs50_project_root_input cs50_project_root_source
unset cs50_host_home cs50_project_root cs50_flake cs50_state_dir cs50_home
unset cs50_check50_path cs50_config_dir cs50_cache_dir cs50_data_dir
unset cs50_runtime_state_dir cs50_tmp_dir cs50_uv_cache_dir cs50_uv_tools_dir
unset cs50_gnupg_dir cs50_git_config cs50_sqlite_history cs50_gdb_history
unset cs50_state_directories cs50_state_files cs50_directory cs50_file
unset cs50_session_dir cs50_cleanup_command cs50_path cs50_git_global_config
unset cs50_host_ssh_config cs50_host_known_hosts cs50_ssh_command
unset cs50_quoted_option cs50_variable variables
