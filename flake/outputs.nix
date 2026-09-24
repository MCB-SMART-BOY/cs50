# Flake output assembly. flake.nix stays thin: it declares inputs (versions
# are pinned by flake.lock) and delegates everything else to the modules
# in this directory.
inputs:
let
  inherit (inputs.nixpkgs) lib;

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  forAllSystems = lib.genAttrs systems;

  # One factory for every consumer (packages, checks, dev shell, overlay),
  # so flake outputs and the overlay can never drift apart.
  mkCs50 =
    pkgs:
    import ./packages.nix {
      inherit pkgs;
      inherit (inputs)
        libcs50
        lib50
        check50
        style50
        submit50
        ;
    };
in
{
  overlays.default = final: _prev: mkCs50 final;

  packages = forAllSystems (
    system:
    let
      cs50 = mkCs50 inputs.nixpkgs.legacyPackages.${system};
    in
    {
      inherit (cs50) libcs50 cs50-tools;
      default = cs50.cs50-tools;
    }
  );

  checks = forAllSystems (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      cs50 = mkCs50 pkgs;
    in
    import ./checks.nix { inherit pkgs cs50; }
  );

  devShells = forAllSystems (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      cs50 = mkCs50 pkgs;
    in
    import ./devshell.nix { inherit pkgs cs50; }
  );

  formatter = forAllSystems (system: inputs.nixpkgs.legacyPackages.${system}.nixfmt);
}
