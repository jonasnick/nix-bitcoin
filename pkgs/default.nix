{ pkgs ? import <nixpkgs> {} }:
{
  nodeinfo = pkgs.callPackage ./nodeinfo { };
  lightning-charge = pkgs.callPackage ./lightning-charge { };
  nanopos = pkgs.callPackage ./nanopos { };
  spark-wallet = pkgs.callPackage ./spark-wallet { };
  electrs = (pkgs.callPackage ./electrs { }).rootCrate.build;
  elementsd = pkgs.callPackage ./elementsd { withGui = false; };
  hwi = pkgs.callPackage ./hwi { };
  pylightning = pkgs.python3Packages.callPackage ./pylightning { };
  liquid-swap = pkgs.python3Packages.callPackage ./liquid-swap { };
  generate-secrets = pkgs.callPackage ./generate-secrets { };

  pinned = import ./pinned.nix;
}
