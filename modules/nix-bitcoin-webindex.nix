{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nix-bitcoin-webindex;
  inherit (config) nix-bitcoin-services;
  indexFile = pkgs.writeText "index.html" ''
    <html>
      <body>
        <p>
          <h1>
            nix-bitcoin
          </h1>
        </p>
        ${optionalString config.services.nanopos.enable ''<p><h2><a href="store/">store</a></h2></p>''}
        <p>
        <h3>
          lightning node: CLIGHTNING_ID
        </h3>
        </p>
      </body>
    </html>
  '';
  createWebIndex = pkgs.writeText "make-index.sh" ''
    set -e
    cp ${indexFile} /var/www/index.html
    chown -R nginx:nginx /var/www/
    nodeinfo
    . <(nodeinfo)
    sed -i "s/CLIGHTNING_ID/$CLIGHTNING_ID/g" /var/www/index.html
  '';
in {
  options.services.nix-bitcoin-webindex = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the webindex service will be installed.
      '';
    };
    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "HTTP server listen address.";
    };
    enforceTor =  nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = config.services.nanopos.enable;
        message = "nix-bitcoin-webindex requires nanopos.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/www 0755 nginx nginx - -"
    ];

    services.nginx = {
      enable = true;
      virtualHosts."_" = {
        root = "/var/www";
      };
    };
    services.tor.hiddenServices.nginx = {
      map = [{
        port = 80; toHost = cfg.host;
      } {
        port = 443; toHost = cfg.host;
      }];
      version = 3;
    };

    # create-web-index
    systemd.services.create-web-index = {
      description = "Get node info";
      wantedBy = [ "multi-user.target" ];
      path  = with pkgs; [
        config.programs.nodeinfo
        config.services.clightning.cli
        config.services.lnd.cli
        jq
        sudo
      ];
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        ExecStart="${pkgs.bash}/bin/bash ${createWebIndex}";
        User = "root";
        Type = "simple";
        RemainAfterExit="yes";
        Restart = "on-failure";
        RestartSec = "10s";
        PrivateNetwork = "true"; # This service needs no network access
        PrivateUsers = "false";
        ReadWritePaths = "/var/www";
        CapabilityBoundingSet = "CAP_SETUID CAP_SETGID CAP_SETPCAP CAP_SYS_ADMIN CAP_CHOWN CAP_FSETID CAP_SETFCAP CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_IPC_OWNER";
      } // (if cfg.enforceTor
          then nix-bitcoin-services.allowTor
          else nix-bitcoin-services.allowAnyIP
        );
    };
  };
}
