{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.liquidd;
  inherit (config) nix-bitcoin-services;
  secretsDir = config.nix-bitcoin.secretsDir;
  pidFile = "${cfg.dataDir}/liquidd.pid";
  configFile = pkgs.writeText "elements.conf" ''
    chain=liquidv1
    ${optionalString cfg.testnet "testnet=1"}
    ${optionalString (cfg.dbCache != null) "dbcache=${toString cfg.dbCache}"}
    ${optionalString (cfg.prune != null) "prune=${toString cfg.prune}"}
    ${optionalString (cfg.validatepegin != null) "validatepegin=${if cfg.validatepegin then "1" else "0"}"}

    # Connection options
    bind=${cfg.bind}
    ${optionalString (cfg.port != null) "port=${toString cfg.port}"}
    ${optionalString (cfg.proxy != null) "proxy=${cfg.proxy}"}
    listen=${if cfg.listen then "1" else "0"}

    # RPC server options
    ${optionalString (cfg.rpc.port != null) "rpcport=${toString cfg.rpc.port}"}
    ${concatMapStringsSep  "\n"
      (rpcUser: "rpcauth=${rpcUser.name}:${rpcUser.passwordHMAC}")
      (attrValues cfg.rpc.users)
    }
    ${lib.concatMapStrings (rpcbind: "rpcbind=${rpcbind}\n") cfg.rpcbind}
    ${lib.concatMapStrings (rpcallowip: "rpcallowip=${rpcallowip}\n") cfg.rpcallowip}
    ${optionalString (cfg.rpcuser != null) "rpcuser=${cfg.rpcuser}"}
    ${optionalString (cfg.rpcpassword != null) "rpcpassword=${cfg.rpcpassword}"}
    ${optionalString (cfg.mainchainrpchost != null) "mainchainrpchost=${cfg.mainchainrpchost}"}

    # Extra config options (from liquidd nixos service)
    ${cfg.extraConfig}
  '';
  cmdlineOptions = concatMapStringsSep " " (arg: "'${arg}'") [
    "-datadir=${cfg.dataDir}"
    "-pid=${pidFile}"
  ];
  hexStr = types.strMatching "[0-9a-f]+";
  rpcUserOpts = { name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        example = "alice";
        description = ''
          Username for JSON-RPC connections.
        '';
      };
      passwordHMAC = mkOption {
        type = with types; uniq (strMatching "[0-9a-f]+\\$[0-9a-f]{64}");
        example = "f7efda5c189b999524f151318c0c86$d5b51b3beffbc02b724e5d095828e0bc8b2456e9ac8757ae3211a5d9b16a22ae";
        description = ''
          Password HMAC-SHA-256 for JSON-RPC connections. Must be a string of the
          format <SALT-HEX>$<HMAC-HEX>.
        '';
      };
    };
    config = {
      name = mkDefault name;
    };
  };
in {
  options = {

    services.liquidd = {
      enable = mkEnableOption "Liquid sidechain";

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        example = ''
          par=16
          rpcthreads=16
          logips=1

        '';
        description = "Additional configurations to be appended to <filename>elements.conf</filename>.";
      };
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/liquidd";
        description = "The data directory for liquidd.";
      };
      bind = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = ''
          Bind to given address and always listen on it.
        '';
      };

      user = mkOption {
        type = types.str;
        default = "liquid";
        description = "The user as which to run liquidd.";
      };
      group = mkOption {
        type = types.str;
        default = cfg.user;
        description = "The group as which to run liquidd.";
      };

      rpc = {
        port = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Override the default port on which to listen for JSON-RPC connections.";
        };
        users = mkOption {
          default = {};
          example = {
            alice.passwordHMAC = "f7efda5c189b999524f151318c0c86$d5b51b3beffbc02b724e5d095828e0bc8b2456e9ac8757ae3211a5d9b16a22ae";
            bob.passwordHMAC = "b2dd077cb54591a2f3139e69a897ac$4e71f08d48b4347cf8eff3815c0e25ae2e9a4340474079f55705f40574f4ec99";
          };
          type = with types; loaOf (submodule rpcUserOpts);
          description = ''
            RPC user information for JSON-RPC connnections.
          '';
        };
      };

      rpcbind = mkOption {
        type = types.listOf types.str;
        default = [ "127.0.0.1" ];
        description = ''
          Bind to given address to listen for JSON-RPC connections.
        '';
      };
      rpcallowip = mkOption {
        type = types.listOf types.str;
        default = [ "127.0.0.1" ];
        description = ''
          Allow JSON-RPC connections from specified source.
        '';
      };
      rpcuser = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Username for JSON-RPC connections";
      };
      rpcpassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Password for JSON-RPC connections";
      };
      mainchainrpchost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The address which the daemon will try to connect to the trusted
          mainchain daemon to validate peg-ins.
        '';
      };

      testnet = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use the test chain.";
      };
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Override the default port on which to listen for connections.";
      };
      proxy = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Connect through SOCKS5 proxy";
      };
      listen = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If enabled, the liquid service will listen.
        '';
      };
      dbCache = mkOption {
        type = types.nullOr (types.ints.between 4 16384);
        default = null;
        example = 4000;
        description = "Override the default database cache size in megabytes.";
      };
      prune = mkOption {
        type = types.nullOr (types.coercedTo
          (types.enum [ "disable" "manual" ])
          (x: if x == "disable" then 0 else 1)
          types.ints.unsigned
        );
        default = null;
        example = 10000;
        description = ''
          Reduce storage requirements by enabling pruning (deleting) of old
          blocks. This allows the pruneblockchain RPC to be called to delete
          specific blocks, and enables automatic pruning of old blocks if a
          target size in MiB is provided. This mode is incompatible with -txindex
          and -rescan. Warning: Reverting this setting requires re-downloading
          the entire blockchain. ("disable" = disable pruning blocks, "manual"
          = allow manual pruning via RPC, >=550 = automatically prune block files
          to stay under the specified target size in MiB)
        '';
      };
      validatepegin = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Validate pegin claims. All functionaries must run this.
        '';
      };
      cli = mkOption {
        default = pkgs.writeScriptBin "elements-cli" ''
          exec ${pkgs.nix-bitcoin.elementsd}/bin/elements-cli -datadir='${cfg.dataDir}' "$@"
        '';
        description = "Binary to connect with the liquidd instance.";
      };
      swap-cli = mkOption {
        default = pkgs.writeScriptBin "liquidswap-cli" ''
          exec ${pkgs.nix-bitcoin.liquid-swap}/bin/liquidswap-cli -c '${cfg.dataDir}/elements.conf' "$@"
        '';
        description = "Binary for managing liquid swaps.";
      };
      enforceTor =  nix-bitcoin-services.enforceTor;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.nix-bitcoin.elementsd
      (hiPrio cfg.cli)
      (hiPrio cfg.swap-cli)
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0770 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.liquidd = {
      description = "Elements daemon providing access to the Liquid sidechain";
      requires = [ "bitcoind.service" ];
      after = [ "bitcoind.service" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        cp '${configFile}' '${cfg.dataDir}/elements.conf'
        chmod 640  '${cfg.dataDir}/elements.conf'
        chown -R '${cfg.user}:${cfg.group}' '${cfg.dataDir}'
        echo "rpcpassword=$(cat ${secretsDir}/liquid-rpcpassword)" >> '${cfg.dataDir}/elements.conf'
        echo "mainchainrpcpassword=$(cat ${secretsDir}/bitcoin-rpcpassword)" >> '${cfg.dataDir}/elements.conf'
      '';
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        Type = "simple";
        User = "${cfg.user}";
        Group = "${cfg.group}";
        ExecStart = "${pkgs.nix-bitcoin.elementsd}/bin/elementsd ${cmdlineOptions}";
        PIDFile = "${pidFile}";
        Restart = "on-failure";
        ReadWritePaths = "${cfg.dataDir}";
      } // (if cfg.enforceTor
          then nix-bitcoin-services.allowTor
          else nix-bitcoin-services.allowAnyIP
        );
    };
    users.users.${cfg.user} = {
      group = cfg.group;
      extraGroups = [ "bitcoinrpc" ];
      description = "Liquid sidechain user";
    };
    users.groups.${cfg.group} = {};
    nix-bitcoin.secrets.liquid-rpcpassword.user = "liquid";
  };
}
