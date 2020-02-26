{
  network.description = "Bitcoin Core node";

  bitcoin-node = { config, pkgs, lib, ... }: {
    imports = [
      ../configuration.nix
      <nix-bitcoin/modules/deployment/nixops.nix>
    ];

    nix-bitcoin.deployment.secretsDir = toString ../secrets;
  };
}
