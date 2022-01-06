{
  # The modules are topologically sorted by their dependencies.
  # This means that modules only depend on modules higher in the list
  # (unless otherwise noted).
  imports = [
    # Core modules
    ./nix-bitcoin.nix
    ./secrets/secrets.nix
    ./operator.nix

    # Main features
    ./bitcoind.nix
    ./clightning.nix
    ./clightning-plugins
    ./clightning-rest.nix
    ./clightning-db-replication.nix
    ./spark-wallet.nix
    ./lnd.nix
    ./lightning-loop.nix
    ./lightning-pool.nix
    ./charge-lnd.nix
    ./lndconnect-onion.nix # Requires onion-addresses.nix
    ./rtl.nix
    ./electrs.nix
    ./liquid.nix
    ./btcpayserver.nix
    ./joinmarket.nix
    ./joinmarket-ob-watcher.nix
    ./hardware-wallets.nix

    # Support features
    ./versioning.nix
    ./security.nix
    ./onion-addresses.nix
    ./onion-services.nix
    ./netns-isolation.nix
    ./nodeinfo.nix
    ./backups.nix
  ];

  disabledModules = [ "services/networking/bitcoind.nix" ];
}
