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
        bash ${./scripts/smoke-libcs50.sh} \
          "${cs50.libcs50}" \
          "${./scripts/hello-libcs50.c}"
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
        bash ${./scripts/smoke-cs50-tools.sh} \
          "${cs50.cs50-tools}/bin/style50" \
          "${./scripts/hello-style.c}" \
          "${./scripts/validate-style50-json.py}"
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
        bash ${./scripts/smoke-check50-pipeline.sh} \
          "${cs50.libcs50}" \
          "${caesar-checks}" \
          "${./scripts/caesar.c}"
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
        bash ${./scripts/smoke-uv-dynamic-dependencies.sh} \
          "${uv-dependency}" \
          "${./scripts/uv-dynamic-dependencies-smoke.py}"
      '';
  # setup-state.sh must keep persistent state below the project root while
  # giving each shell its own disposable TMPDIR session.
  state-isolation-smoke = pkgs.runCommand "cs50-state-isolation-smoke" { } ''
    bash ${./scripts/smoke-state-isolation.sh} \
      "${./scripts/setup-state.sh}"
  '';
}
