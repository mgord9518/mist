{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  nativeBuildInputs = with pkgs.buildPackages; [
    zig_0_13
    go
    rustc
    gnumake
  ];
}
