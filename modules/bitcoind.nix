{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.bitcoind;
  inherit (config) nix-bitcoin-services;

  configFile = pkgs.writeText "bitcoin.conf" ''
    # We're already logging via journald
    nodebuglogfile=1

    ${optionalString cfg.testnet "testnet=1"}
    ${optionalString (cfg.dbCache != null) "dbcache=${toString cfg.dbCache}"}
    "prune=${toString cfg.prune}
    ${optionalString (cfg.sysperms != null) "sysperms=${if cfg.sysperms then "1" else "0"}"}
    ${optionalString (cfg.disablewallet != null) "disablewallet=${if cfg.disablewallet then "1" else "0"}"}
    ${optionalString (cfg.assumevalid != null) "assumevalid=${cfg.assumevalid}"}

    # Connection options
    bind=${cfg.bind}
    ${optionalString (cfg.port != null) "port=${toString cfg.port}"}
    ${optionalString (cfg.proxy != null) "proxy=${cfg.proxy}"}
    listen=${if cfg.listen then "1" else "0"}
    ${optionalString (cfg.discover != null) "discover=${if cfg.discover then "1" else "0"}"}
    ${lib.concatMapStrings (node: "addnode=${node}\n") cfg.addnodes}

    # RPC server options
    rpcport=${toString cfg.rpc.port}
    ${concatMapStringsSep  "\n"
      (rpcUser: "rpcauth=${rpcUser.name}:${rpcUser.passwordHMAC}")
      (attrValues cfg.rpc.users)
    }
    ${lib.concatMapStrings (rpcbind: "rpcbind=${rpcbind}\n") cfg.rpcbind}
    ${lib.concatMapStrings (rpcallowip: "rpcallowip=${rpcallowip}\n") cfg.rpcallowip}
    ${optionalString (cfg.rpcuser != null) "rpcuser=${cfg.rpcuser}"}
    ${optionalString (cfg.rpcpassword != null) "rpcpassword=${cfg.rpcpassword}"}

    # Wallet options
    ${optionalString (cfg.addresstype != null) "addresstype=${cfg.addresstype}"}

    # ZMQ options
    ${optionalString (cfg.zmqpubrawblock != null) "zmqpubrawblock=${cfg.zmqpubrawblock}"}
    ${optionalString (cfg.zmqpubrawtx != null) "zmqpubrawtx=${cfg.zmqpubrawtx}"}

    # Extra options
    ${cfg.extraConfig}
  '';
in {
  options = {
    services.bitcoind = {
      enable = mkEnableOption "Bitcoin daemon";
      package = mkOption {
        type = types.package;
        default = pkgs.nix-bitcoin.bitcoind;
        defaultText = "pkgs.blockchains.bitcoind";
        description = "The package providing bitcoin binaries.";
      };
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        example = ''
          par=16
          rpcthreads=16
          logips=1
        '';
        description = "Additional configurations to be appended to <filename>bitcoin.conf</filename>.";
      };
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/bitcoind";
        description = "The data directory for bitcoind.";
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
        default = "bitcoin";
        description = "The user as which to run bitcoind.";
      };
      group = mkOption {
        type = types.str;
        default = cfg.user;
        description = "The group as which to run bitcoind.";
      };
      rpc = {
        port = mkOption {
          type = types.port;
          default = 8332;
          description = "Port on which to listen for JSON-RPC connections.";
        };
        users = mkOption {
          default = {};
          example = {
            alice.passwordHMAC = "f7efda5c189b999524f151318c0c86$d5b51b3beffbc02b724e5d095828e0bc8b2456e9ac8757ae3211a5d9b16a22ae";
            bob.passwordHMAC = "b2dd077cb54591a2f3139e69a897ac$4e71f08d48b4347cf8eff3815c0e25ae2e9a4340474079f55705f40574f4ec99";
          };
          type = with types; loaOf (submodule ({ name, ... }: {
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
          }));
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
          default = "bitcoinrpc";
          description = "Username for JSON-RPC connections";
      };
      rpcpassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Password for JSON-RPC connections";
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
          If enabled, the bitcoin service will listen.
        '';
      };
      dataDirReadableByGroup = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If enabled, data dir content is readable by the bitcoind service group.
          Warning: This disables bitcoind's wallet support.
        '';
      };
      sysperms = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Create new files with system default permissions, instead of umask 077
          (only effective with disabled wallet functionality)
        '';
      };
      disablewallet = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Do not load the wallet and disable wallet RPC calls
        '';
      };
      dbCache = mkOption {
        type = types.nullOr (types.ints.between 4 16384);
        default = null;
        example = 4000;
        description = "Override the default database cache size in megabytes.";
      };
      prune = mkOption {
        type = types.ints.unsigned;
        default = 0;
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
      zmqpubrawblock = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "tcp://127.0.0.1:28332";
        description = "ZMQ address for zmqpubrawblock notifications";
      };
      zmqpubrawtx = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "tcp://127.0.0.1:28333";
        description = "ZMQ address for zmqpubrawtx notifications";
      };
      assumevalid = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "00000000000000000000e5abc3a74fe27dc0ead9c70ea1deb456f11c15fd7bc6";
        description = ''
          If this block is in the chain assume that it and its ancestors are
          valid and potentially skip their script verification.
        '';
      };
      addnodes = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "ecoc5q34tmbq54wl.onion" ];
        description = "Add nodes to connect to and attempt to keep the connections open";
      };
      discover = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Discover own IP addresses";
      };
      addresstype = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "bech32";
        description = "What type of addresses to use";
      };
      cli = mkOption {
        type = types.package;
        readOnly = true;
        default = pkgs.writeScriptBin "bitcoin-cli" ''
          exec ${cfg.package}/bin/bitcoin-cli -datadir='${cfg.dataDir}' "$@"
        '';
        description = "Binary to connect with the bitcoind instance.";
      };
      enforceTor =  nix-bitcoin-services.enforceTor;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package (hiPrio cfg.cli) ];

    services.bitcoind = mkIf cfg.dataDirReadableByGroup {
      disablewallet = true;
      sysperms = true;
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0770 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataDir}/blocks' 0770 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.bitcoind = {
      description = "Bitcoin daemon";
      requires = [ "nix-bitcoin-secrets.target" ];
      after = [ "network.target" "nix-bitcoin-secrets.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        ${optionalString cfg.dataDirReadableByGroup  "chmod -R g+rX '${cfg.dataDir}/blocks'"}

        cfg=$(cat ${configFile}; printf "rpcpassword="; cat "${config.nix-bitcoin.secretsDir}/bitcoin-rpcpassword")
        confFile='${cfg.dataDir}/bitcoin.conf'
        if [[ ! -e $confFile || $cfg != $(cat $confFile) ]]; then
          install -o '${cfg.user}' -g '${cfg.group}' -m 640  <(echo "$cfg") $confFile
        fi
      '';
      # Wait until RPC port is open. This usually takes just a few ms.
      postStart = ''
        while ! { exec 3>/dev/tcp/127.0.0.1/${toString cfg.rpc.port}; } &>/dev/null; do
          sleep 0.05
        done
      '';
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        User = "${cfg.user}";
        Group = "${cfg.group}";
        ExecStart = "${cfg.package}/bin/bitcoind -datadir='${cfg.dataDir}'";
        Restart = "on-failure";
        UMask = mkIf cfg.dataDirReadableByGroup "0027";
        ReadWritePaths = "${cfg.dataDir}";
      } // (if cfg.enforceTor
            then nix-bitcoin-services.allowTor
            else nix-bitcoin-services.allowAnyIP)
        // optionalAttrs (cfg.zmqpubrawblock != null || cfg.zmqpubrawtx != null) nix-bitcoin-services.allowAnyProtocol;
    };

    # Use this to update the banlist:
    # wget https://people.xiph.org/~greg/banlist.cli.txt
    systemd.services.bitcoind-import-banlist = {
      description = "Bitcoin daemon banlist importer";
      wantedBy = [ "bitcoind.service" ];
      bindsTo = [ "bitcoind.service" ];
      after = [ "bitcoind.service" ];
      script = ''
        cd ${cfg.cli}/bin
        # Poll until bitcoind accepts commands. This can take a long time.
        while ! ./bitcoin-cli getnetworkinfo &> /dev/null; do
          sleep 1
        done
        echo "Importing node banlist..."
        cat ${./banlist.cli.txt} | while read line; do
            if ! err=$(eval "$line" 2>&1) && [[ $err != *already\ banned* ]]; then
                # unexpected error
                echo "$err"
                exit 1
            fi
        done
      '';
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        User = "${cfg.user}";
        Group = "${cfg.group}";
        ReadWritePaths = "${cfg.dataDir}";
      } // nix-bitcoin-services.allowTor;
    };

    users.users.${cfg.user} = {
      group = cfg.group;
      description = "Bitcoin daemon user";
    };
    users.groups.${cfg.group} = {};
    users.groups.bitcoinrpc = {};

    nix-bitcoin.secrets.bitcoin-rpcpassword = {
      user = "bitcoin";
      group = "bitcoinrpc";
    };
  };
}
