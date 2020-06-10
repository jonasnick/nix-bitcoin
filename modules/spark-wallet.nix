{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.spark-wallet;
  inherit (config) nix-bitcoin-services;
  onion-chef-service = (if cfg.onion-service then [ "onion-chef.service" ] else []);
  run-spark-wallet = pkgs.writeScript "run-spark-wallet" ''
    CMD="${pkgs.nix-bitcoin.spark-wallet}/bin/spark-wallet --ln-path ${cfg.ln-path} --host ${cfg.host} -Q -k -c ${config.nix-bitcoin.secretsDir}/spark-wallet-login ${cfg.extraArgs}"
    ${optionalString cfg.onion-service
      ''
      echo Getting onion hostname
      CMD="$CMD --public-url http://$(cat /var/lib/onion-chef/spark-wallet/spark-wallet)"
      ''
    }
    # Use rate provide wasabi because default (bitstamp) doesn't accept
    # connections through Tor and add proxy for rate lookup.
    CMD="$CMD --rate-provider wasabi --proxy socks5h://${config.services.tor.client.socksListenAddress}"
    echo Running $CMD
    $CMD
  '';
in {
  options.services.spark-wallet = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the spark-wallet service will be installed.
      '';
    };
    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "http(s) server listen address.";
    };
    ln-path = mkOption {
      type = types.path;
      default = "${config.services.clightning.dataDir}/bitcoin";
      description = ''
        "The path of the clightning network data directory.";
      '';
    };
    onion-service = mkOption {
      type = types.bool;
      default = false;
      description = ''
        "If enabled, configures spark-wallet to be reachable through an onion service.";
      '';
    };
    extraArgs = mkOption {
      type = types.separatedString " ";
      default = "";
      description = "Extra command line arguments passed to spark-wallet.";
    };
    enforceTor =  nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = config.services.clightning.enable;
        message = "spark-wallet requires clightning.";
      }
    ];

    environment.systemPackages = [ pkgs.nix-bitcoin.spark-wallet ];
    users.users.spark-wallet = {
      description = "spark-wallet User";
      group = "spark-wallet";
      extraGroups = [ "clightning" ];
    };
    users.groups.spark-wallet = {};

    services.tor.enable = cfg.onion-service;
    # requires client functionality for Bitcoin rate lookup
    services.tor.client.enable = true;
    services.tor.hiddenServices.spark-wallet = mkIf cfg.onion-service {
      map = [{
        port = 80; toPort = 9737; toHost = cfg.host;
      }];
      version = 3;
    };
    services.onion-chef.enable = cfg.onion-service;
    services.onion-chef.access.spark-wallet = if cfg.onion-service then [ "spark-wallet" ] else [];
    systemd.services.spark-wallet = {
      description = "Run spark-wallet";
      wantedBy = [ "multi-user.target" ];
      requires = [ "clightning.service" ] ++ onion-chef-service;
      after = [ "clightning.service" ]  ++ onion-chef-service;
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        ExecStart = "${pkgs.bash}/bin/bash ${run-spark-wallet}";
        User = "spark-wallet";
        Restart = "on-failure";
        RestartSec = "10s";
        ReadWritePaths = "/var/lib/onion-chef";
      } // (if cfg.enforceTor
            then nix-bitcoin-services.allowTor
            else nix-bitcoin-services.allowAnyIP)
        // nix-bitcoin-services.nodejs;
    };
    nix-bitcoin.secrets.spark-wallet-login.user = "spark-wallet";
  };
}
