# All CS50 package definitions. Imported by flake/outputs.nix (and reusable
# anywhere else) with:
#
#   import ./packages.nix { inherit pkgs; inherit (inputs) libcs50 lib50 check50 style50 submit50; }
#
# Returns { libcs50, cs50-tools }. The same module body also serves as the
# flake overlay, so flake outputs and overlays can never drift apart.
{
  pkgs,
  libcs50,
  lib50,
  check50,
  style50,
  submit50,
}:
let
  # Python 3.13, not the default interpreter: check50's
  # ProcessPoolExecutor relies on module state inherited through
  # fork(), which Python 3.14 no longer defaults to on Linux.
  ps = pkgs.python313Packages;

  libcs50-pkg = pkgs.stdenv.mkDerivation rec {
    pname = "libcs50";
    version = "11.0.4";
    src = libcs50;

    nativeBuildInputs = [
      pkgs.clang
      pkgs.gnumake
    ];
    makeFlags = [ "CC=clang" ];
    # The pinned nixpkgs strip hook references an unset variable under
    # `set -u`; this small library does not need post-install stripping.
    dontStrip = true;

    # Upstream `make install` runs ldconfig, which mutates system
    # state; install the same layout manually instead.
    installPhase = ''
      runHook preInstall
      bash ${./scripts/install-libcs50.sh} \
        "$out" \
        "${version}" \
        "${pkgs.lib.versions.major version}"
      runHook postInstall
    '';

    meta = {
      description = "CS50 library for C (cs50.h, get_string, ...)";
      homepage = "https://github.com/cs50/libcs50";
      license = pkgs.lib.licenses.gpl3Only;
      platforms = pkgs.lib.platforms.linux;
    };
  };

  lib50-pkg = ps.buildPythonPackage {
    pname = "lib50";
    version = "3.2.3";
    format = "setuptools";
    src = lib50;

    propagatedBuildInputs = [
      ps.cryptography
      ps.jellyfish
      ps.packaging
      ps.pexpect
      ps.pyyaml
      ps.requests
      ps.setuptools
      ps.termcolor
    ];

    # Upstream tests need network access (they clone GitHub repos).
    doCheck = false;
    pythonImportsCheck = [ "lib50" ];

    meta = {
      description = "CS50's internal library, used by check50/style50/submit50";
      homepage = "https://github.com/cs50/lib50";
      license = pkgs.lib.licenses.gpl3Only;
      platforms = pkgs.lib.platforms.linux;
    };
  };

  check50-pkg = ps.buildPythonPackage {
    pname = "check50";
    version = "3.4.0";
    format = "setuptools";
    src = check50;
    postPatch = ''
      bash ${./scripts/patch-check50-uv.sh} check50/__main__.py ${./scripts/check50-uv-install-dependencies.py}
    '';

    propagatedBuildInputs = [
      lib50-pkg
      ps.attrs
      ps.beautifulsoup4
      ps.jinja2
      ps.packaging
      ps.pexpect
      ps.pyyaml
      ps.requests
      ps.setuptools
      ps.termcolor
    ];

    doCheck = false;
    pythonImportsCheck = [ "check50" ];

    meta = {
      description = "Check the correctness of CS50 programs";
      homepage = "https://github.com/cs50/check50";
      license = pkgs.lib.licenses.gpl3Only;
      mainProgram = "check50";
      platforms = pkgs.lib.platforms.linux;
    };
  };

  style50-pkg = ps.buildPythonPackage {
    pname = "style50";
    version = "3.0.0";
    format = "setuptools";
    src = style50;

    # style50 invokes clang-format and djhtml as external binaries; the
    # runtime package below carries them directly, not as PyPI dependencies.
    propagatedBuildInputs = [
      ps.autopep8
      ps.cssbeautifier
      ps.icdiff
      ps.jinja2
      ps.jsbeautifier
      ps.pycodestyle
      ps."python-magic"
      ps.sqlparse
      ps.termcolor
    ];

    doCheck = false;
    pythonImportsCheck = [ "style50" ];

    meta = {
      description = "Check code against the CS50 style guide";
      homepage = "https://github.com/cs50/style50";
      license = pkgs.lib.licenses.gpl3Only;
      mainProgram = "style50";
      platforms = pkgs.lib.platforms.linux;
    };
  };

  submit50-pkg = ps.buildPythonPackage {
    pname = "submit50";
    version = "3.2.1";
    format = "setuptools";
    src = submit50;

    propagatedBuildInputs = [
      lib50-pkg
      ps.packaging
      ps.pytz
      ps.requests
      ps.setuptools
      ps.termcolor
    ];

    doCheck = false;
    pythonImportsCheck = [ "submit50" ];

    meta = {
      description = "Submit solutions to CS50 problems";
      homepage = "https://github.com/cs50/submit50";
      license = pkgs.lib.licenses.gpl3Only;
      mainProgram = "submit50";
      platforms = pkgs.lib.platforms.linux;
    };
  };
  cs50-tools-python = pkgs.python313.withPackages (_: [
    check50-pkg
    style50-pkg
    submit50-pkg
  ]);
in
{
  libcs50 = libcs50-pkg;

  # Keep uv in the same runtime environment as check50. Dynamic check
  # dependencies are installed by the patched check50 entry point via uv,
  # never by a user-level package installer.
  cs50-tools = pkgs.symlinkJoin {
    name = "cs50-tools";
    # Keep the external style checkers in the same runtime closure as the
    # Python entry points, so standalone packages and overlays work too.
    paths = [
      cs50-tools-python
      pkgs.uv
      pkgs.clang-tools
      pkgs.djhtml
    ];
  };
}
