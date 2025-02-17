{
  description = "MIST plugin development shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default =
      import ./shell.nix { pkgs = nixpkgs.legacyPackages.x86_64-linux; };

    packages.aarch64-linux.default =
      import ./shell.nix { pkgs = nixpkgs.legacyPackages.aarch64-linux; };
  };
}
