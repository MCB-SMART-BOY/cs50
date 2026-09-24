# Offline sandbox smoke tests for `nix flake check`. Each test builds the
# real packages and exercises them end to end. The C/Python/YAML fixtures
# live as plain files in scripts/ next to this one; this module only holds
# the build-and-assert logic.
{
  pkgs,
  cs50,
}:
let
  # A minimal vendored checks package (in the spirit of cs50/problems'
  # caesar checks), so the pipeline test below can run fully offline via
  # check50's development mode (-d), which reads checks from a local
  # directory with no GitHub access.
  caesar-checks = pkgs.runCommand "cs50-caesar-checks" { } ''
    set -euo pipefail
    mkdir -p "$out"
    cp -a "${./scripts/caesar-checks}/." "$out/"
  '';
  # Local package used to exercise dynamic check dependencies without
  # network access. The patched check50 installs it through uv.
  uv-dependency = pkgs.runCommand "cs50-uv-dependency" { } ''
    set -euo pipefail
    mkdir -p "$out"
    cp -a "${./scripts/uv-dependency}/." "$out/"
  '';

in
{
  # Compile and run a cs50.h program, both directly with clang and via
  # make's implicit rules (`make hello`), as in the CS50 codespace.
  libcs50-smoke =
    pkgs.runCommand "cs50-libcs50-smoke"
      {
        nativeBuildInputs = [
          pkgs.clang
          pkgs.gnumake
        ];
        # The codespace's plain clang does not define _FORTIFY_SOURCE;
        # at -O0 glibc would #warning about it and -Werror would fail.
        hardeningDisable = [ "fortify" ];
      }
      ''
        set -euo pipefail
        export C_INCLUDE_PATH="${cs50.libcs50}/include"
        export LIBRARY_PATH="${cs50.libcs50}/lib"
        export LD_LIBRARY_PATH="${cs50.libcs50}/lib"
        export CC=clang
        export CFLAGS="-ggdb3 -O0 -std=c17 -Wall -Werror -Wextra -Wno-sign-compare -Wno-unused-parameter -Wshadow"
        export LDLIBS="-lcs50 -lm"

        cp "${./scripts/hello-libcs50.c}" hello.c

        clang hello.c -lcs50 -lm -o hello-direct
        test "$(printf 'World\n' | ./hello-direct)" = "Name: hello, World"

        make hello
        test "$(printf 'Make\n' | ./hello)" = "Name: hello, Make"

        touch "$out"
      '';

  # The three CS50 tools must run offline: --help/--version, imports
  # (including python-magic's libmagic) and a real style50 C-format
  # pass, which shells out to clang-format.
  cs50-tools-smoke =
    pkgs.runCommand "cs50-tools-smoke"
      {
        nativeBuildInputs = [
          cs50.cs50-tools
        ];
      }
      ''
          set -euo pipefail
          export HOME="$TMPDIR"

          check50 --help > /dev/null
          submit50 --help > /dev/null
          style50 --version > /dev/null
        cp "${./scripts/hello-style.c}" hello.c
        ${pkgs.style50}/bin/style50 -o json hello.c > style-results.json
        python -c '
        import json
        from pathlib import Path

        result = json.loads(Path("style-results.json").read_text())
        required = {"files", "score", "version"}
        if not isinstance(result, dict) or not required.issubset(result):
            raise SystemExit("style50 JSON output is missing required fields")
        if not result["files"]:
            raise SystemExit("style50 JSON output did not include hello.c")
        hello_result = next(
            (file for file in result["files"] if file.get("name") == "hello.c"),
            None,
        )
        if hello_result is None:
            raise SystemExit("style50 JSON output did not identify hello.c")
        if hello_result.get("score") != 1:
            raise SystemExit("style50 JSON output reported a failing file")
        '
        test -s style-results.json
        touch "$out"
      '';

  # check50's full local pipeline, offline: the vendored caesar-checks
  # package plus a correct student solution must pass all three checks
  # and exit 0. This is what catches breakage like Python 3.14's
  # fork-server default breaking check50's ProcessPoolExecutor.
  check50-pipeline-smoke =
    pkgs.runCommand "cs50-check50-pipeline-smoke"
      {
        nativeBuildInputs = [
          cs50.cs50-tools
          cs50.libcs50
          pkgs.clang
        ];
      }
      ''
        set -euo pipefail
        export HOME="$TMPDIR"
        export C_INCLUDE_PATH="${cs50.libcs50}/include"
        export LIBRARY_PATH="${cs50.libcs50}/lib"
        export LD_LIBRARY_PATH="${cs50.libcs50}/lib"

        mkdir student
        cd student
        cp "${./scripts/caesar.c}" caesar.c

        check50 -d "${caesar-checks}" -o json > results.json

        # All three checks passed and check50 exited 0.
        test "$(grep -c '"passed": true' results.json)" -eq 3
        ! grep -q '"passed": false' results.json
        touch "$out"
      '';

  # Prove the dynamic dependency path itself: check50's replacement
  # function must install a local package with uv, make it importable in
  # the current process, and expose it to a child Python process.
  uv-dynamic-dependencies-smoke =
    pkgs.runCommand "cs50-uv-dynamic-dependencies-smoke"
      {
        nativeBuildInputs = [ cs50.cs50-tools ];
      }
      ''
        set -euo pipefail
        export HOME="$TMPDIR"
        export CS50_TEST_INHERITED_MARKER=must-not-reach-uv
        export UV_CACHE_DIR="$TMPDIR/uv-cache"
        export CS50_UV_DEPENDENCY="cs50-uv-dependency @ file://${uv-dependency}"

        python "${./scripts/uv-dynamic-dependencies-smoke.py}"
        touch "$out"
      '';
  # setup-state.sh must keep persistent state below the project root while
  # giving each shell its own disposable TMPDIR session.
  state-isolation-smoke = pkgs.runCommand "cs50-state-isolation-smoke" { } ''
    set -euo pipefail

    smoke_root="$TMPDIR/cs50-state-isolation"
    project_root="$smoke_root/project"
    mkdir -p "$project_root"
    printf '%s\n' '{ description = "cs50 state isolation smoke"; }' > "$project_root/flake.nix"
    cp "${./scripts/setup-state.sh}" "$project_root/setup-state.sh"

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

    session_dir="$(cat "$smoke_root/session-path")"
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
  '';
}
