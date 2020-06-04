{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.clightning;
  inherit (config) nix-bitcoin-services;
  onion-chef-service = (if cfg.announce-tor then [ "onion-chef.service" ] else []);
  configFile = pkgs.writeText "config" ''
    network=bitcoin
    bitcoin-datadir=${config.services.bitcoind.dataDir}
    ${optionalString (cfg.proxy != null) "proxy=${cfg.proxy}"}
    always-use-proxy=${if cfg.always-use-proxy then "true" else "false"}
    ${optionalString (cfg.bind-addr != null) "bind-addr=${cfg.bind-addr}"}
    bitcoin-rpcuser=${cfg.bitcoin-rpcuser}
    rpc-file-mode=0660
  '';
in {
  options.services.clightning = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the clightning service will be installed.
      '';
    };
    autolisten = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Bind (and maybe announce) on IPv4 and IPv6 interfaces if no addr,
        bind-addr or  announce-addr  options  are specified.
      '';
    };
    proxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Set a socks proxy to use to connect to Tor nodes (or for all connections if *always-use-proxy* is set)";
    };
    always-use-proxy = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Always use the *proxy*, even to connect to normal IP addresses (you can still connect to Unix domain sockets manually). This also disables all DNS lookups, to avoid leaking information.
      '';
    };
    bind-addr = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Set an IP address or UNIX domain socket to listen to";
    };
    announce-tor = mkOption {
      type = types.bool;
      default = false;
      description = "Announce clightning Tor Hidden Service";
    };
    bitcoin-rpcuser = mkOption {
      type = types.str;
      description = ''
        Bitcoin RPC user
      '';
    };
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/clightning";
      description = "The data directory for clightning.";
    };
    user = mkOption {
      type = types.str;
      default = "clightning";
      description = "The user as which to run clightning.";
    };
    group = mkOption {
      type = types.str;
      default = cfg.user;
      description = "The group as which to run clightning.";
    };
    cli = mkOption {
      readOnly = true;
      default = pkgs.writeScriptBin "lightning-cli"
      ''
        ${pkgs.nix-bitcoin.clightning}/bin/lightning-cli --lightning-dir='${cfg.dataDir}' "$@"
      '';
      description = "Binary to connect with the clightning instance.";
    };
    enforceTor =  nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.nix-bitcoin.clightning (hiPrio cfg.cli) ];
    users.users.${cfg.user} = {
        description = "clightning User";
        group = cfg.group;
        extraGroups = [ "bitcoinrpc" ];
    };
    users.groups.${cfg.group} = {};

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0770 ${cfg.user} ${cfg.group} - -"
    ];

    services.onion-chef.access.clightning = if cfg.announce-tor then [ "clightning" ] else [];
    systemd.services.clightning = {
      description = "Run clightningd";
      path  = [ pkgs.nix-bitcoin.bitcoind ];
      wantedBy = [ "multi-user.target" ];
      requires = [ "bitcoind.service" ] ++ onion-chef-service;
      after = [ "bitcoind.service" ] ++ onion-chef-service;
      preStart = ''
        cp ${configFile} ${cfg.dataDir}/config
        chown -R '${cfg.user}:${cfg.group}' '${cfg.dataDir}'
        # The RPC socket has to be removed otherwise we might have stale sockets
        rm -f ${cfg.dataDir}/bitcoin/lightning-rpc
        chmod 600 ${cfg.dataDir}/config
        echo "bitcoin-rpcpassword=$(cat ${config.nix-bitcoin.secretsDir}/bitcoin-rpcpassword)" >> '${cfg.dataDir}/config'
        ${optionalString cfg.announce-tor "echo announce-addr=$(cat /var/lib/onion-chef/clightning/clightning) >> '${cfg.dataDir}/config'"}
        '';
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        ExecStart = "${pkgs.nix-bitcoin.clightning}/bin/lightningd --lightning-dir=${cfg.dataDir}";
        User = "${cfg.user}";
        Restart = "on-failure";
        RestartSec = "10s";
        ReadWritePaths = "${cfg.dataDir}";
      } // (if cfg.enforceTor
          then nix-bitcoin-services.allowTor
          else nix-bitcoin-services.allowAnyIP
        );
      # Wait until the rpc socket appears
      postStart = ''
        while [[ ! -e ${cfg.dataDir}/bitcoin/lightning-rpc ]]; do
            sleep 0.1
        done
        # Needed to enable lightning-cli for users with group 'clightning'
        chmod g+x ${cfg.dataDir}/bitcoin
      '';
    };
  };
}
