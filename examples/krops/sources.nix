{ extraSources, krops }:

krops.lib.evalSource [({
  nixos-config.symlink = "krops/krops-configuration.nix";

  # Only include krops-configuration.nix from krops dir
  "krops".file = {
    path = toString ../krops;
    filters = [{
      type = "include";
      pattern = "krops-configuration.nix";
    }{
      type = "exclude";
      pattern = "*";
    }];
  };

  "configuration.nix".file = toString ../configuration.nix;

  # Enable `useChecksum` for sources which might be located in the nix store
  # and which therefore might have static timestamps.

  nixpkgs.file = {
    path = toString <nixpkgs>;
    useChecksum = true;
  };

  nix-bitcoin.file = {
    path = toString <nix-bitcoin>;
    useChecksum = true;
    filters = [{
      type = "exclude";
      pattern = ".git";
    }];
  };

  secrets.file = toString ../secrets;
} // extraSources)]
