{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services;

  operatorName = config.nix-bitcoin.operatorName;

  mkHiddenService = map: {
    map = [ map ];
    version = 3;
  };
in {
  imports = [
    ../modules.nix
    ../nodeinfo.nix
    ../nix-bitcoin-webindex.nix
  ];

  options = {
    services.clightning.onionport = mkOption {
      type = types.port;
      default = 9735;
      description = "Port on which to listen for tor client connections.";
    };
    services.lnd.onionport = mkOption {
      type = types.ints.u16;
      default = 9735;
      description = "Port on which to listen for tor client connections.";
    };
    services.electrs.onionport = mkOption {
      type = types.port;
      default = 50002;
      description = "Port on which to listen for tor client connections.";
    };
    nix-bitcoin.operatorName = mkOption {
      type = types.str;
      default = "operator";
      description = "Less-privileged user's name.";
    };
  };

  config =  {
    # For backwards compatibility only
    nix-bitcoin.secretsDir = mkDefault "/secrets";

    networking.firewall.enable = true;

    # Tor
    services.tor = {
      enable = true;
      client.enable = true;
      # LND uses ControlPort to create onion services
      controlPort = mkIf cfg.lnd.enable 9051;

      hiddenServices.sshd = mkHiddenService { port = 22; };
    };

    # netns-isolation
    nix-bitcoin.netns-isolation = {
      enable = false;
      addressblock = 1;
    };

    # bitcoind
    services.bitcoind = {
      enable = true;
      listen = true;
      dataDirReadableByGroup = mkIf cfg.electrs.high-memory true;
      proxy = cfg.tor.client.socksListenAddress;
      enforceTor = true;
      port = 8333;
      assumevalid = "00000000000000000000e5abc3a74fe27dc0ead9c70ea1deb456f11c15fd7bc6";
      addnodes = [ "ecoc5q34tmbq54wl.onion" ];
      discover = false;
      addresstype = "bech32";
      dbCache = 1000;
    };
    services.tor.hiddenServices.bitcoind = mkHiddenService { port = cfg.bitcoind.port; toHost = cfg.bitcoind.bind; };

    # clightning
    services.clightning = {
      proxy = cfg.tor.client.socksListenAddress;
      enforceTor = true;
      always-use-proxy = true;
    };
    services.tor.hiddenServices.clightning = mkHiddenService { port = cfg.clightning.onionport; toHost = (builtins.head (builtins.split ":" cfg.clightning.bind-addr)); };

    # lnd
    services.lnd = {
      tor-socks = cfg.tor.client.socksListenAddress;
      enforceTor = true;
    };
    services.tor.hiddenServices.lnd = mkHiddenService { port = cfg.lnd.onionport; toHost = cfg.lnd.listen; };

    # liquidd
    services.liquidd = {
      rpcuser = "liquidrpc";
      prune = 1000;
      extraConfig = ''
        mainchainrpcuser=${cfg.bitcoind.rpcuser}
        mainchainrpcport=8332
      '';
      validatepegin = true;
      listen = true;
      proxy = cfg.tor.client.socksListenAddress;
      enforceTor = true;
      port = 7042;
    };
    services.tor.hiddenServices.liquidd = mkHiddenService { port = cfg.liquidd.port; toHost = cfg.liquidd.bind; };

    # electrs
    services.electrs = {
      port = 50001;
      enforceTor = true;
      TLSProxy.enable = true;
      TLSProxy.port = 50003;
    };
    services.tor.hiddenServices.electrs = mkHiddenService {
      port = cfg.electrs.onionport;
      toPort = if cfg.electrs.TLSProxy.enable then cfg.electrs.TLSProxy.port else cfg.electrs.port;
      toHost = cfg.electrs.host;
    };

    services.spark-wallet = {
      onion-service = true;
      enforceTor = true;
    };

    services.lightning-charge.enforceTor = true;

    services.nanopos.enforceTor = true;

    services.recurring-donations.enforceTor = true;

    services.nix-bitcoin-webindex.enforceTor = true;


    environment.systemPackages = with pkgs; [
      tor
      jq
      qrencode
    ];

    # Create operator user which can access the node's services
    users.users.${operatorName} = {
      isNormalUser = true;
      extraGroups = [
          "systemd-journal"
          cfg.bitcoind.group
        ]
        ++ (optionals cfg.clightning.enable [ "clightning" ])
        ++ (optionals cfg.lnd.enable [ "lnd" ])
        ++ (optionals cfg.liquidd.enable [ cfg.liquidd.group ])
        ++ (optionals (cfg.hardware-wallets.ledger || cfg.hardware-wallets.trezor)
            [ cfg.hardware-wallets.group ]);
      openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
    };
    # Give operator access to onion hostnames
    services.onion-chef.enable = true;
    services.onion-chef.access.${operatorName} = [ "bitcoind" "clightning" "nginx" "liquidd" "spark-wallet" "electrs" "sshd" ];

    security.sudo.configFile =
     (optionalString cfg.lnd.enable ''
       ${operatorName}    ALL=(lnd) NOPASSWD: ALL
     '');

    # Enable nixops ssh for operator (`nixops ssh operator@mynode`) on nixops-vbox deployments
    systemd.services.get-vbox-nixops-client-key =
      mkIf (builtins.elem ".vbox-nixops-client-key" config.services.openssh.authorizedKeysFiles) {
        postStart = ''
          cp "${config.users.users.root.home}/.vbox-nixops-client-key" "${config.users.users.${operatorName}.home}"
        '';
      };
  };
}
