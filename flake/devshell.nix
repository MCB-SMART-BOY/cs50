# The interactive CS50 development shell (`nix develop`).
{
  pkgs,
  cs50,
}:
{
  default = pkgs.mkShell {
    packages = [
      cs50.libcs50
      # cs50-tools carries uv plus style50's clang-format and djhtml.
      cs50.cs50-tools
      pkgs.clang
      pkgs.gdb
      pkgs.git # check50/submit50 talk to GitHub
      pkgs.gnumake
      pkgs.sqlite
      pkgs.valgrind
      # Nix lint tooling for the repository's configured lint gate.
      pkgs.deadnix
      pkgs.statix
    ];

    # Match the codespace's plain clang: without this, NixOS's clang wrapper
    # would inject _FORTIFY_SOURCE, which glibc warns about at -O0 and
    # -Werror would turn into an error.
    hardeningDisable = [ "fortify" ];

    # Make libcs50 discoverable so that `clang hello.c -lcs50 -o hello`
    # and make's implicit rules (`make hello`) work as in the codespace.
    C_INCLUDE_PATH = "${cs50.libcs50}/include";
    LIBRARY_PATH = "${cs50.libcs50}/lib";
    LD_LIBRARY_PATH = "${cs50.libcs50}/lib";
    # The dynamic check dependency installer uses this trusted Nix-store binary.
    CS50_UV = "${pkgs.uv}/bin/uv";

    # The flags CS50's codespace passes to make/clang.
    CFLAGS = "-ggdb3 -O0 -std=c17 -Wall -Werror -Wextra -Wno-sign-compare -Wno-unused-parameter -Wshadow";
    LDLIBS = "-lcs50 -lm";
    LDFLAGS = "-Wl,-rpath,${cs50.libcs50}/lib";

    shellHook = ''
      # stdenv's setup hooks would otherwise leave make's ''$(CC) at gcc.
      export CC=clang

      # setup-state.sh resolves one canonical project root and confines
      # persistent tool state to its .cs50 directory. It fails closed before
      # exporting anything when the root or state layout is unsafe.
      # From a subdirectory, set CS50_PROJECT_ROOT_OVERRIDE explicitly; a
      # previously entered CS50 shell is never reused as the new root.
      if ! source ${./scripts/setup-state.sh}; then
        exit 1
      fi
      echo "CS50 dev shell ready (state: $CS50_STATE_DIR). Try:"
      echo "  make hello                            # compile with codespace flags"
      echo "  clang hello.c -lcs50 -lm -o hello     # or explicit clang"
      echo "  style50 hello.c                       # style check"
      echo "  check50 cs50/problems/2026/x/caesar  # -l runs locally; remote needs auth"
      echo "  submit50 cs50/problems/2026/x/caesar # needs https://submit.cs50.io auth"
      echo "  CS50_PROJECT_ROOT_OVERRIDE=/path nix develop # from a subdirectory"
      echo "  CS50_PRESERVE_HOST_GIT_CONFIG=1 # opt into host Git config"
      echo "  CS50_PRESERVE_HOST_SSH=1         # opt into host SSH config"
      echo "  session temp: $CS50_SESSION_DIR       # removed on shell exit"
    '';
  };
}
