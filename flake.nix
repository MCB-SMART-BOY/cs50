{
  description = "CS50 development environment: libcs50 + check50 + style50 + submit50";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    libcs50 = {
      url = "github:cs50/libcs50/v11.0.4";
      flake = false;
    };
    lib50 = {
      # lib50 has no v3.x tags (latest tag is v2.0.9, incompatible with
      # check50's lib50>=3,<4 requirement); track main, pinned by flake.lock.
      url = "github:cs50/lib50";
      flake = false;
    };
    check50 = {
      url = "github:cs50/check50/v3.4.0";
      flake = false;
    };
    style50 = {
      url = "github:cs50/style50/v3.0.0";
      flake = false;
    };
    submit50 = {
      url = "github:cs50/submit50/v3.2.1";
      flake = false;
    };
  };

  outputs = inputs: import ./flake/outputs.nix inputs;
}
