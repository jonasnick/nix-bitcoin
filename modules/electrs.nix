{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.electrs;
  inherit (config) nix-bitcoin-services;
  secretsDir = config.nix-bitcoin.secretsDir;
in {
  imports = [
    (mkRenamedOptionModule [ "services" "electrs" "nginxport" ] [ "services" "electrs" "TLSProxy" "port" ])
  ];

  options.services.electrs = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the electrs service will be installed.
      '';
    };
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/electrs";
      description = "The data directory for electrs.";
    };
    user = mkOption {
      type = types.str;
      default = "electrs";
      description = "The user as which to run electrs.";
    };
    group = mkOption {
      type = types.str;
      default = cfg.user;
      description = "The group as which to run electrs.";
    };
    high-memory = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the electrs service will sync faster on high-memory systems (≥ 8GB).
      '';
    };
    port = mkOption {
      type = types.ints.u16;
      default = 50001;
      description = "RPC port.";
    };
    onionport = mkOption {
      type = types.ints.u16;
      default = 50002;
      description = "Port on which to listen for tor client connections.";
    };
    TLSProxy = {
      enable = mkEnableOption "Nginx TLS proxy";
      port = mkOption {
        type = types.ints.u16;
        default = 50003;
        description = "Port on which to listen for TLS client connections.";
      };
    };
    enforceTor = nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable (mkMerge [{
    systemd.services.electrs = {
      description = "Run electrs";
      wantedBy = [ "multi-user.target" ];
      requires = [ "bitcoind.service" ];
      after = [ "bitcoind.service" ];
      # create shell script to start up electrs safely with password parameter
      preStart = ''
        mkdir -m 0770 -p ${cfg.dataDir}
        chown -R '${cfg.user}:${cfg.group}' ${cfg.dataDir}
        echo "${pkgs.nix-bitcoin.electrs}/bin/electrs -vvv" \
             ${optionalString (!cfg.high-memory) "--jsonrpc-import --index-batch-size=10"} \
             "--db-dir ${cfg.dataDir} --daemon-dir /var/lib/bitcoind" \
             "--cookie=${config.services.bitcoind.rpcuser}:$(cat ${secretsDir}/bitcoin-rpcpassword)" \
             "--electrum-rpc-addr=127.0.0.1:${toString cfg.port}" > /run/electrs/startscript.sh
        '';
      serviceConfig = rec {
        RuntimeDirectory = "electrs";
        RuntimeDirectoryMode = "700";
        PermissionsStartOnly = "true";
        ExecStart = "${pkgs.bash}/bin/bash /run/${RuntimeDirectory}/startscript.sh";
        User = "electrs";
        Restart = "on-failure";
        RestartSec = "10s";
      } // nix-bitcoin-services.defaultHardening
        // (if cfg.enforceTor
          then nix-bitcoin-services.allowTor
          else nix-bitcoin-services.allowAnyIP
        );
    };

    users.users.${cfg.user} = {
      description = "electrs User";
      group = cfg.group;
      extraGroups = [ "bitcoinrpc" "bitcoin"];
      home = cfg.dataDir;
    };
    users.groups.${cfg.group} = {};
  }

  (mkIf cfg.TLSProxy.enable {
    services.nginx = {
      enable = true;
      appendConfig = ''
        stream {
          upstream electrs {
            server 127.0.0.1:${toString cfg.port};
          }

          server {
            listen ${toString cfg.TLSProxy.port} ssl;
            proxy_pass electrs;

            ssl_certificate ${secretsDir}/nginx-cert;
            ssl_certificate_key ${secretsDir}/nginx-key;
            ssl_session_cache shared:SSL:1m;
            ssl_session_timeout 4h;
            ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
            ssl_prefer_server_ciphers on;
          }
        }
      '';
    };
    systemd.services = {
      electrs.wants = [ "nginx.service" ];
      nginx = {
        requires = [ "nix-bitcoin-secrets.target" ];
        after = [ "nix-bitcoin-secrets.target" ];
      };
    };
    nix-bitcoin.secrets = rec {
      nginx-key = {
        user = "nginx";
        group = "root";
      };
      nginx-cert = nginx-key;
    };
  })
  ]);
}
