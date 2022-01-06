# Integration tests, can be run without internet access.

let
  nixpkgs = (import ../pkgs/nixpkgs-pinned.nix).nixpkgs;
in

{ extraScenarios ? { ... }: {}
, pkgs ? import nixpkgs { config = {}; overlays = []; }
}:
with pkgs.lib;
let
  globalPkgs = pkgs;

  baseConfig = { pkgs, config, ... }: let
    cfg = config.services;
    mkIfTest = test: mkIf (config.tests.${test} or false);
  in {
    imports = [
      ./lib/test-lib.nix
      ../modules/modules.nix
      {
        # Features required by the Python test suite
        nix-bitcoin.secretsDir = "/secrets";
        nix-bitcoin.generateSecrets = true;
        nix-bitcoin.operator.enable = true;
        environment.systemPackages = with pkgs; [ jq ];
      }
    ];

    options.test.features = {
      clightningPlugins = mkEnableOption "all clightning plugins";
    };

    config = mkMerge [{
      # Share the same pkgs instance among tests
      nixpkgs.pkgs = mkDefault globalPkgs;

      tests.bitcoind = cfg.bitcoind.enable;
      services.bitcoind = {
        enable = true;
        extraConfig = mkIf config.test.noConnections "connect=0";
      };

      tests.clightning = cfg.clightning.enable;
      test.data.clightning-replication = cfg.clightning.replication.enable;
      services.clightning.replication = {
        enable = true;
        encrypt = true;
        local.directory = "/var/backup/clightning";
      };
      # When WAN is disabled, DNS bootstrapping slows down service startup by ~15 s.
      services.clightning.extraConfig = mkIf config.test.noConnections "disable-dns";
      test.data.clightning-plugins = let
        plugins = config.services.clightning.plugins;
        enabled = builtins.filter (plugin: plugins.${plugin}.enable) (builtins.attrNames plugins);
        nbPkgs = config.nix-bitcoin.pkgs;
        pluginPkgs = nbPkgs.clightning-plugins // {
          clboss.path = "${nbPkgs.clboss}/bin/clboss";
        };
      in map (plugin: pluginPkgs.${plugin}.path) enabled;
      # Torified 'dig' subprocesses of clboss don't respond to SIGTERM and keep
      # running for a long time when WAN is disabled, which prevents clightning units
      # from stopping quickly.
      # Set TimeoutStopSec for faster stopping.
      systemd.services.clightning.serviceConfig.TimeoutStopSec =
        mkIf config.services.clightning.plugins.clboss.enable "500ms";

      tests.clightning-rest = cfg.clightning-rest.enable;

      tests.rtl = cfg.rtl.enable;
      services.rtl.nodes.lnd = mkDefault true;
      services.rtl.nodes.clightning = mkDefault true;
      services.rtl.loop = mkIf cfg.rtl.nodes.lnd (mkDefault true);
      # Use a simple, non-random password for manual web interface tests
      nix-bitcoin.generateSecretsCmds.rtl = mkIf cfg.rtl.enable (mkForce ''
        echo a > rtl-password
      '');
      services.rtl.extraCurrency = mkDefault "CHF";

      tests.spark-wallet = cfg.spark-wallet.enable;

      tests.lnd = cfg.lnd.enable;
      services.lnd.port = 9736;

      tests.lndconnect-onion-lnd = cfg.lnd.lndconnectOnion.enable;
      tests.lndconnect-onion-clightning = cfg.clightning-rest.lndconnectOnion.enable;

      tests.lightning-loop = cfg.lightning-loop.enable;

      tests.lightning-pool = cfg.lightning-pool.enable;
      nix-bitcoin.onionServices.lnd.public = true;

      tests.charge-lnd = cfg.charge-lnd.enable;

      tests.electrs = cfg.electrs.enable;

      tests.liquidd = cfg.liquidd.enable;
      services.liquidd.extraConfig = mkIf config.test.noConnections "connect=0";

      tests.btcpayserver = cfg.btcpayserver.enable;
      services.btcpayserver = {
        lightningBackend = mkDefault "lnd";
        lbtc = mkDefault true;
      };
      # Needed to test macaroon creation
      environment.systemPackages = mkIfTest "btcpayserver" (with pkgs; [ openssl xxd ]);
      test.data.btcpayserver-lbtc = config.services.btcpayserver.lbtc;

      tests.joinmarket = cfg.joinmarket.enable;
      tests.joinmarket-yieldgenerator = cfg.joinmarket.yieldgenerator.enable;
      tests.joinmarket-ob-watcher = cfg.joinmarket-ob-watcher.enable;
      services.joinmarket.yieldgenerator = {
        enable = config.services.joinmarket.enable;
        # Test a smattering of custom parameters
        ordertype = "absoffer";
        cjfee_a = 300;
        cjfee_r = 0.00003;
        txfee = 200;
      };

      tests.nodeinfo = config.nix-bitcoin.nodeinfo.enable;

      tests.backups = cfg.backups.enable;

      # To test that unused secrets are made inaccessible by 'setup-secrets'
      systemd.services.setup-secrets.preStart = mkIfTest "security" ''
        install -D -o nobody -g nogroup -m777 <(:) /secrets/dummy
      '';

      # Avoid timeout failures on slow CI nodes
      systemd.services.postgresql.serviceConfig.TimeoutStartSec = "3min";
    }
    (mkIf config.test.features.clightningPlugins {
      services.clightning.plugins = {
        clboss.enable = true;
        helpme.enable = true;
        monitor.enable = true;
        prometheus.enable = true;
        rebalance.enable = true;
        summary.enable = true;
        commando = {
          enable = true;
          readers = [ "0266e4598d1d3c415f572a8488830b60f7e744ed9235eb0b1ba93283b315c03518" ];
          writers = [ "0336efaa22b8ba77ae721a25d589e1c5f2486073dd2f041add32a23316150e8b62" ];
        };
        zmq = let tcpEndpoint = "tcp://127.0.0.1:5501"; in {
          enable = true;
          channel-opened = tcpEndpoint;
          connect = tcpEndpoint;
          disconnect = tcpEndpoint;
          invoice-payment = tcpEndpoint;
          warning = tcpEndpoint;
          forward-event = tcpEndpoint;
          sendpay-success = tcpEndpoint;
          sendpay-failure = tcpEndpoint;
        };
      };
    })
    ];
  };

  scenarios = {
    base = baseConfig; # Included in all scenarios

    default = scenarios.secureNode;

    # All available basic services and tests
    full = {
      tests.security = true;

      services.clightning.enable = true;
      test.features.clightningPlugins = true;
      services.rtl.enable = true;
      services.spark-wallet.enable = true;
      services.clightning-rest.enable = true;
      services.clightning-rest.lndconnectOnion.enable = true;
      services.lnd.enable = true;
      services.lnd.lndconnectOnion.enable = true;
      services.lightning-loop.enable = true;
      services.lightning-pool.enable = true;
      services.charge-lnd.enable = true;
      services.electrs.enable = true;
      services.liquidd.enable = true;
      services.btcpayserver.enable = true;
      services.joinmarket.enable = true;
      services.joinmarket-ob-watcher.enable = true;
      services.backups.enable = true;

      nix-bitcoin.nodeinfo.enable = true;

      services.hardware-wallets = {
        trezor = true;
        ledger = true;
      };
    };

    secureNode = {
      imports = [
        scenarios.full
        ../modules/presets/secure-node.nix
      ];
      tests.secure-node = true;
      tests.banlist-and-restart = true;

      # Stop electrs from spamming the test log with 'WARN - wait until IBD is over' messages
      tests.stop-electrs = true;
    };

    netns = {
      imports = with scenarios; [ netnsBase secureNode ];
      # This test is rather slow and unaffected by netns settings
      tests.backups = mkForce false;
    };

    # All regtest-enabled services
    regtest = {
      imports = [ scenarios.regtestBase ];
      services.clightning.enable = true;
      test.features.clightningPlugins = true;
      services.clightning-rest.enable = true;
      services.liquidd.enable = true;
      services.rtl.enable = true;
      services.spark-wallet.enable = true;
      services.lnd.enable = true;
      services.lightning-loop.enable = true;
      services.lightning-pool.enable = true;
      services.charge-lnd.enable = true;
      services.electrs.enable = true;
      services.btcpayserver.enable = true;
      services.joinmarket.enable = true;
    };

    # netns and regtest, without secure-node.nix
    netnsRegtest = {
      imports = with scenarios; [ netnsBase regtest ];
    };

    hardened = {
      imports = [
        scenarios.secureNode
        ../modules/presets/hardened-extended.nix
      ];
    };

    netnsBase = { config, pkgs, ... }: {
      nix-bitcoin.netns-isolation.enable = true;
      test.data.netns = config.nix-bitcoin.netns-isolation.netns;
      tests.netns-isolation = true;
      environment.systemPackages = [ pkgs.fping ];
    };

    regtestBase = { config, ... }: {
      tests.regtest = true;
      test.data.num_blocks = 100;

      services.bitcoind.regtest = true;
      systemd.services.bitcoind.postStart = mkAfter ''
        cli=${config.services.bitcoind.cli}/bin/bitcoin-cli
        if ! $cli listwallets | ${pkgs.jq}/bin/jq -e 'index("test")'; then
          $cli -named createwallet  wallet_name=test load_on_startup=true
          address=$($cli -rpcwallet=test getnewaddress)
          $cli generatetoaddress ${toString config.test.data.num_blocks} $address
        fi
      '';

      # lightning-loop contains no builtin swap server for regtest.
      # Add a dummy definition.
      services.lightning-loop.extraConfig = ''
        server.host=localhost
      '';

      # lightning-pool contains no builtin auction server for regtest.
      # Add a dummy definition
      services.lightning-pool.extraConfig = ''
        auctionserver=localhost
      '';

      # `validatepegin` is incompatible with regtest
      services.liquidd.validatepegin = mkForce false;

      # TODO-EXTERNAL:
      # Reenable `btcpayserver.lbtc` in regtest (and add test in tests.py)
      # when nbxplorer can parse liquidd regtest blocks.
      #
      # When `btcpayserver.lbtc` is enabled in regtest, nxbplorer tries to
      # generate regtest blocks, which fails because no liquidd wallet exists.
      # When blocks are pre-generated via `liquidd.postStart`, nbxplorer
      # fails to parse the blocks:
      #   info: NBXplorer.Indexer.LBTC: Full node version detected: 210002
      #   info: NBXplorer.Indexer.LBTC: NBXplorer is correctly whitelisted by the node
      #     fail: NBXplorer.Indexer.LBTC: Unhandled exception in the indexer, retrying in 10 seconds
      #       System.IO.EndOfStreamException: No more byte to read
      #         at NBitcoin.BitcoinStream.ReadWriteBytes(Span`1 data)
      services.btcpayserver.lbtc = mkForce false;
    };

    ## Examples / debug helper

    # Run a selection of tests in scenario 'netns'
    selectedTests = {
      imports = [ scenarios.netns ];
      tests = mkForce {
        btcpayserver = true;
        netns-isolation = true;
      };
    };

    # Container-specific features
    containerFeatures = {
      # Container has WAN access and bitcoind connects to external nodes
      test.container.enableWAN = true;
      # See ./lib/test-lib.nix for a description
      test.container.exposeLocalhost = true;
    };

    adhoc = {
      # <Add your config here>
      # You can also set the env var `scenarioOverridesFile` (used below) to define custom scenarios.
    };
  };

  overrides = builtins.getEnv "scenarioOverridesFile";
  extraScenarios' = (if (overrides != "") then import overrides else extraScenarios) {
    inherit scenarios pkgs;
    inherit (pkgs) lib;
  };
  allScenarios = scenarios // extraScenarios';

  makeTest = name: config:
    makeTest' name {
      imports = [
        allScenarios.base
        config
      ];
    };
  makeTest' = import ./lib/make-test.nix pkgs;

  tests = builtins.mapAttrs makeTest allScenarios;

  getTest = name: tests.${name} or (makeTest name {
    services.${name}.enable = true;
  });
in
  tests // {
    inherit getTest;
  }
