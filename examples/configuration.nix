# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }: {
  imports = [
    <nix-bitcoin/modules/nix-bitcoin.nix>

    # FIXME: The hardened kernel profile improves security but
    # decreases performance by ~50%.
    # Turn it off when not needed.
    # Source: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/hardened.nix
    <nixpkgs/nixos/modules/profiles/hardened.nix>

    # FIXME: Uncomment next line to import your hardware configuration. If so,
    # add the hardware configuration file to the same directory as this file.
    # This is not needed when deploying to a virtual box.
    #./hardware-configuration.nix
  ];
  # FIXME: Enable modules by uncommenting their respective line. Disable
  # modules by commenting out their respective line.  Enable this module to
  # use the nix-bitcoin node configuration. Only disable this if you know what
  # you are doing.
  services.nix-bitcoin.enable = true;

  ### BITCOIND
  # Bitcoind is enabled by default if nix-bitcoin is enabled
  #
  # You can override default settings from nix-bitcoin.nix as follows
  # services.bitcoind.prune = lib.mkForce 100000;
  #
  # You can add options that are not defined in modules/bitcoind.nix as follows
  # services.bitcoind.extraConfig = ''
  #   maxorphantx=110
  # '';

  ### CLIGHTNING
  # Enable this module to use clightning, a Lightning Network implementation
  # in C.
  services.clightning.enable = true;
  # Enable this option to listen for incoming lightning connections. By
  # default nix-bitcoin nodes offer outgoing connectivity.
  # services.clightning.autolisten = true;

  ### LND
  # Disable clightning and uncomment the following line in order to enable lnd,
  # a lightning implementation written in Go.
  # services.lnd.enable = assert (!config.services.clightning.enable); true;
  ## WARNING
  # If you use lnd, you should manually backup your wallet mnemonic
  # seed. This will allow you to recover on-chain funds. You can run the
  # following command after the lnd service starts:
  # nixops scp --from bitcoin-node /secrets/lnd-seed-mnemonic ./secrets/lnd-seed-mnemonic
  # You should also backup your channel state after opening new channels.
  # This will allow you to recover off-chain funds, by force-closing channels.
  # nixops scp --from bitcoin-node /var/lib/lnd/chain/bitcoin/mainnet/channel.backup /my-backup-path/channel.backup

  ### SPARK WALLET
  # Enable this module to use spark-wallet, a minimalistic wallet GUI for
  # c-lightning, accessible over the web or through mobile and desktop apps.
  # Only enable this if clightning is enabled.
  # services.spark-wallet.enable = true;

  ### ELECTRS
  # Enable this module to use electrs, an efficient re-implementation of
  # Electrum Server in Rust. Only enable this if hardware wallets are
  # disabled.
  # services.electrs.enable = true;
  # If you have ≥8GB memory, enable this option so electrs will sync faster.
  # services.electrs.high-memory = true;

  ### LIQUIDD
  # Enable this module to use Liquid, a sidechain for an inter-exchange
  # settlement network linking together cryptocurrency exchanges and
  # institutions around the world. Liquid is accessed with the elements-cli
  # tool run as user operator.
  # services.liquidd.enable = true;

  ### LIGHTNING CHARGE
  # Enable this module to use lightning-charge, a simple drop-in solution for
  # accepting lightning payments. Only enable this if clightning is enabled.
  # services.lightning-charge.enable = true;

  ### NANOPOS
  # Enable this module to use nanopos, a simple Lightning point-of-sale
  # system, powered by Lightning Charge. Only enable this if clightning and
  # lightning-charge are enabled.
  # services.nanopos.enable = true;

  ### WEBINDEX
  # Enable this module to use the nix-bitcoin-webindex, a simple website
  # displaying your node information and link to nanopos store. Only enable
  # this if clightning, lightning-charge, and nanopos are enabled.
  # services.nix-bitcoin-webindex.enable = true;

  ### RECURRING-DONATIONS
  # Enable this module to send recurring donations. This is EXPERIMENTAL; it's
  # not guaranteed that payments are succeeding or that you will notice payment
  # failure. Only enable this if clightning is enabled.
  # services.recurring-donations.enable = true;
  # Specify the receivers of the donations. By default donations are every
  # Monday at a randomized time. Check `journalctl -eu recurring-donations` or
  # `lightning-cli listpayments` for successful lightning donations.
  # services.recurring-donations.tallycoin = {
  #   "<receiver name>" = <amount you wish to donate in sat>"
  #   "<additional receiver name>" = <amount you wish to donate in sat>;
  #   "djbooth007" = 1000;
  # };

  ### Hardware wallets
  # Enable this module to allow using hardware wallets. See https://github.com/bitcoin-core/HWI
  # for more information. Only enable this if electrs is disabled.
  # Ledger must be initialized through the official ledger live app and the Bitcoin app must
  # be installed and running on the device.
  # services.hardware-wallets.ledger = true;
  # Trezor can be initialized with the trezorctl command in nix-bitcoin. More information in
  # `docs/usage.md`.
  # services.hardware-wallets.trezor = true;

  # FIXME: Define your hostname.
  networking.hostName = "nix-bitcoin";
  time.timeZone = "UTC";

  # FIXME: Add your SSH pubkey
  services.openssh.enable = true;
  users.users.root = {
    openssh.authorizedKeys.keys = [ "" ];
  };

  # FIXME: add packages you need in your system
  environment.systemPackages = with pkgs; [
    vim
  ];

  # FIXME: Add custom options (like boot options, output of
  # nixos-generate-config, etc.):

  # If the hardened profile is imported above, we need to explicitly allow
  # user namespaces to enable sanboxed builds and services.
  security.allowUserNamespaces = true;

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "18.09"; # Did you read the comment?
}
