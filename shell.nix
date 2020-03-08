let
  nixpkgs = (import ./pkgs/nixpkgs-pinned.nix).nixpkgs;
in
with import nixpkgs {};

stdenv.mkDerivation rec {
  name = "nix-bitcoin-environment";

  shellHook = ''
    export NIX_PATH="nixpkgs=${nixpkgs}:nix-bitcoin=./:."
  '';
}
