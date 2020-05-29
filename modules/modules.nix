{ config, pkgs, lib, ... }:

{
  imports = [
    ./bitcoind.nix
    ./clightning.nix
    ./lightning-charge.nix
    ./nanopos.nix
    ./liquid.nix
    ./spark-wallet.nix
    ./electrs.nix
    ./onion-chef.nix
    ./recurring-donations.nix
    ./hardware-wallets.nix
    ./lnd.nix
    ./secrets/secrets.nix
    ./netns-isolation.nix
  ];

  disabledModules = [ "services/networking/bitcoind.nix" ];

  options = {
    nix-bitcoin-services = lib.mkOption {
      readOnly = true;
      default = import ./nix-bitcoin-services.nix lib pkgs;
    };
  };

  config = {
    assertions = [
      # lnd.wantedBy == [] needed for `test/tests.nix` in which both clightning and lnd are enabled
      { assertion = config.services.lnd.enable -> (!config.services.clightning.enable || config.systemd.services.lnd.wantedBy == []);
        message = ''
          LND and clightning can't be run in parallel because they both bind to lightning port 9735.
        '';
      }
    ];

    nixpkgs.overlays = [ (self: super: {
      nix-bitcoin = let
        pkgs = import ../pkgs { pkgs = super; };
      in
        pkgs // pkgs.pinned;
    }) ];
  };
}
