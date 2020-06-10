{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.lightning-charge;
  inherit (config) nix-bitcoin-services;
  user = config.users.users.lightning-charge.name;
  group = config.users.users.lightning-charge.group;
in {
  options.services.lightning-charge = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the lightning-charge service will be installed.
      '';
    };
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/lightning-charge";
      description = "The data directory for lightning-charge.";
    };
    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "http server listen address";
    };
    extraArgs = mkOption {
      type = types.separatedString " ";
      default = "";
      description = "Extra command line arguments passed to lightning-charge.";
    };
    enforceTor =  nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = config.services.clightning.enable;
        message = "lightning-charge requires clightning.";
      }
    ];

    users.users.lightning-charge = {
      description = "lightning-charge User";
      group = "lightning-charge";
      extraGroups = [ "clightning" ];
    };
    users.groups.lightning-charge = {};

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0700 ${user} ${group} - -"
    ];

    environment.systemPackages = [ pkgs.nix-bitcoin.lightning-charge ];
    systemd.services.lightning-charge = {
      description = "Run lightning-charge";
      wantedBy = [ "multi-user.target" ];
      requires = [ "clightning.service" ];
      after = [ "clightning.service" ];
      preStart = ''
        # Move existing lightning-charge.db
        # TODO: Remove eventually
        if [[ -e ${config.services.clightning.dataDir}/lightning-charge.db ]]; then
          mv ${config.services.clightning.dataDir}/lightning-charge.db ${cfg.dataDir}/lightning-charge.db
          chown ${user}: ${cfg.dataDir}/lightning-charge.db
          chmod 600 ${cfg.dataDir}/lightning-charge.db
        fi
        '';
      serviceConfig = nix-bitcoin-services.defaultHardening // {
          # Needed to access clightning.dataDir in preStart
          PermissionsStartOnly = "true";
          EnvironmentFile = "${config.nix-bitcoin.secretsDir}/lightning-charge-env";
          ExecStart = "${pkgs.nix-bitcoin.lightning-charge}/bin/charged -l ${config.services.clightning.dataDir}/bitcoin -d ${cfg.dataDir}/lightning-charge.db -i ${cfg.host} ${cfg.extraArgs}";
          User = user;
          Restart = "on-failure";
          RestartSec = "10s";
          ReadWritePaths = "${cfg.dataDir}";
      } // (if cfg.enforceTor
            then nix-bitcoin-services.allowTor
            else nix-bitcoin-services.allowAnyIP)
        // nix-bitcoin-services.nodejs;
    };
    nix-bitcoin.secrets.lightning-charge-env.user = user;
  };
}
