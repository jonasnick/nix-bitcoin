{ pkgs ? import <nixpkgs> {} }:
{
  lightning-charge = pkgs.callPackage ./lightning-charge { };
  nanopos = pkgs.callPackage ./nanopos { };
  spark-wallet = pkgs.callPackage ./spark-wallet { };
  electrs = pkgs.callPackage ./electrs { };
  elementsd = pkgs.callPackage ./elementsd { withGui = false; };
  hwi = pkgs.callPackage ./hwi { };
  pylightning = pkgs.python3Packages.callPackage ./pylightning { };
  liquid-swap = pkgs.python3Packages.callPackage ./liquid-swap { };
  generate-secrets = pkgs.callPackage ./generate-secrets { };
  nixops19_09 = pkgs.callPackage ./nixops { };
  netns-exec = pkgs.callPackage ./netns-exec { };

  pinned = import ./pinned.nix;
}
