{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nanopos;
  inherit (config) nix-bitcoin-services;
  defaultItemsFile = pkgs.writeText "items.yaml" ''
    tea:
      price: 0.02 # denominated in the currency specified by --currency
      title: Green Tea # title is optional, defaults to the key

    coffee:
      price: 1

    bamba:
      price: 3

    beer:
      price: 7

    hat:
      price: 15

    tshirt:
      price: 25
  '';

in {
  options.services.nanopos = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the nanopos service will be installed.
      '';
    };
    port = mkOption {
      type = types.port;
      default = 9116;
      description = ''
        "The port on which to listen for connections.";
      '';
    };
    itemsFile = mkOption {
      type = types.path;
      default = defaultItemsFile;
      description = ''
        "The items file (see nanopos README).";
      '';
    };
    charged-url = mkOption {
      type = types.str;
      default = "http://localhost:9112";
      description = ''
        "The lightning charge server url.";
      '';
    };
    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        "http server listen address.";
      '';
    };
    extraArgs = mkOption {
      type = types.separatedString " ";
      default = "";
      description = "Extra command line arguments passed to nanopos.";
    };
    enforceTor =  nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = config.services.lightning-charge.enable;
        message = "nanopos requires lightning-charge.";
      }
    ];

    environment.systemPackages = [ pkgs.nix-bitcoin.nanopos ];

    services.nginx = {
      enable = true;
      virtualHosts."_" = {
        root = "/var/www";
        extraConfig = ''
          location /store/ {
            proxy_pass http://${toString cfg.host}:${toString cfg.port};
            rewrite /store/(.*) /$1 break;
          }
        '';
      };
    };

    systemd.services.nanopos = {
      description = "Run nanopos";
      wantedBy = [ "multi-user.target" ];
      requires = [ "lightning-charge.service" ];
      after = [ "lightning-charge.service" ];
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        EnvironmentFile = "${config.nix-bitcoin.secretsDir}/nanopos-env";
        ExecStart = "${pkgs.nix-bitcoin.nanopos}/bin/nanopos -y ${cfg.itemsFile} -i ${toString cfg.host} -p ${toString cfg.port} -c ${toString cfg.charged-url} --show-bolt11 ${cfg.extraArgs}";
        User = "nanopos";
        Restart = "on-failure";
        RestartSec = "10s";
      } // (if cfg.enforceTor
            then nix-bitcoin-services.allowTor
            else nix-bitcoin-services.allowAnyIP)
        // nix-bitcoin-services.nodejs;
    };
    users.users.nanopos = {
      description = "nanopos User";
      group = "nanopos";
    };
    users.groups.nanopos = {};
    nix-bitcoin.secrets.nanopos-env.user = "nanopos";
  };
}
