{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.nix-bitcoin.netns-isolation;

  netns = builtins.mapAttrs (n: v: {
    inherit (v) id;
    address = "169.254.${toString cfg.addressblock}.${toString v.id}";
    availableNetns = builtins.filter isEnabled availableNetns.${n};
  }) enabledServices;

  # Symmetric netns connection matrix
  # if clightning.connections = [ "bitcoind" ]; then
  #   availableNetns.bitcoind = [ "clighting" ];
  #   and
  #   availableNetns.clighting = [ "bitcoind" ];
  availableNetns = let
    # base = { clightning = [ "bitcoind" ]; ... }
    base = builtins.mapAttrs (n: v:
      builtins.filter isEnabled v.connections
    ) enabledServices;
  in
    foldl (xs: s1:
      foldl (xs: s2:
        xs // { "${s2}" = xs.${s2} ++ [ s1 ]; }
      ) xs cfg.services.${s1}.connections
    ) base (builtins.attrNames base);

  enabledServices = filterAttrs (n: v: isEnabled n) cfg.services;
  isEnabled = x: config.services.${x}.enable;

  ip = "${pkgs.iproute}/bin/ip";
  iptables = "${config.networking.firewall.package}/bin/iptables";

  bridgeIp = "169.254.${toString cfg.addressblock}.10";

in {
  options.nix-bitcoin.netns-isolation = {
    enable = mkEnableOption "netns isolation";

    addressblock = mkOption {
      type = types.ints.u8;
      default = "1";
      description = ''
        Specify the N address block in 169.254.N.0/24.
      '';
    };

    services = mkOption {
      default = {};
      type = types.attrsOf (types.submodule {
        options = {
          id = mkOption {
            # TODO: Exclude 10
            # TODO: Assert uniqueness
            type = types.int;
            description = ''
              id for the netns, that is used for the IP address host part and
              naming the interfaces. Must be unique. Must not be 10.
            '';
          };
          connections = mkOption {
            type = with types; listOf str;
            default = [];
          };
        };
      });
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      # Prerequisites
      networking.dhcpcd.denyInterfaces = [ "br0" "br-nb*" "nb-veth*" ];
      services.tor.client.socksListenAddress = "${bridgeIp}:9050";
      networking.firewall.interfaces.br0.allowedTCPPorts = [ 9050 ];
      boot.kernel.sysctl."net.ipv4.ip_forward" = true;
      security.wrappers.netns-exec = {
        source  = "${pkgs.nix-bitcoin.netns-exec}/netns-exec";
        capabilities = "cap_sys_admin=ep";
        owner = "${config.nix-bitcoin.operatorName}";
        permissions = "u+rx,g+rx,o-rwx";
      };

      nix-bitcoin.netns-isolation.services = {
        bitcoind = {
          id = 12;
        };
      };

      systemd.services = {
        netns-bridge = {
          description = "Create bridge";
          requiredBy = [ "tor.service" ];
          before = [ "tor.service" ];
          script = ''
            ${ip} link add name br0 type bridge
            ${ip} link set br0 up
            ${ip} addr add ${bridgeIp}/24 brd + dev br0
            ${iptables} -w -t nat -A POSTROUTING -s 169.254.${toString cfg.addressblock}.0/24 -j MASQUERADE
          '';
          preStop = ''
            ${iptables} -w -t nat -D POSTROUTING -s 169.254.${toString cfg.addressblock}.0/24 -j MASQUERADE
            ${ip} link del br0
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = "yes";
          };
        };

        bitcoind-import-banlist.serviceConfig.NetworkNamespacePath = "/var/run/netns/nb-bitcoind";
      } //
      (let
        makeNetnsServices = n: v: let
          vethName = "nb-veth-${toString v.id}";
          netnsName = "nb-${n}";
          ipNetns = "${ip} -n ${netnsName}";
          netnsIptables = "${ip} netns exec ${netnsName} ${config.networking.firewall.package}/bin/iptables";
        in {
          "${n}".serviceConfig.NetworkNamespacePath = "/var/run/netns/${netnsName}";

          "netns-${n}" = rec {
            requires = [ "netns-bridge.service" ];
            after = [ "netns-bridge.service" ];
            bindsTo = [ "${n}.service" ];
            requiredBy = bindsTo;
            before = bindsTo;
            script = ''
              ${ip} netns add ${netnsName}
              ${ipNetns} link set lo up
              ${ip} link add ${vethName} type veth peer name br-${vethName}
              ${ip} link set ${vethName} netns ${netnsName}
              ${ipNetns} addr add ${v.address}/24 dev ${vethName}
              ${ip} link set br-${vethName} up
              ${ipNetns} link set ${vethName} up
              ${ip} link set br-${vethName} master br0
              ${ipNetns} route add default via ${bridgeIp}
              ${netnsIptables} -w -P INPUT DROP
              ${netnsIptables} -w -A INPUT -s 127.0.0.1,${bridgeIp},${v.address} -j ACCEPT
            '' + (optionalString (config.services.${n}.enforceTor or false)) ''
              ${netnsIptables} -w -P OUTPUT DROP
              ${netnsIptables} -w -A OUTPUT -d 127.0.0.1,${bridgeIp},${v.address} -j ACCEPT
            '' + concatMapStrings (otherNetns: let
              other = netns.${otherNetns};
            in ''
              ${netnsIptables} -w -A INPUT -s ${other.address} -j ACCEPT
              ${netnsIptables} -w -A OUTPUT -d ${other.address} -j ACCEPT
            '') v.availableNetns;
            preStop = ''
              ${ip} netns delete ${netnsName}
              ${ip} link del br-${vethName}
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
              ExecStartPre = "-${ip} netns delete ${netnsName}";
            };
          };
        };
      in foldl (services: n:
        services // (makeNetnsServices n netns.${n})
      ) {} (builtins.attrNames netns));

      # bitcoin: Custom netns configs
      services.bitcoind = {
        bind = netns.bitcoind.address;
        rpcbind = [
          "${netns.bitcoind.address}"
          "127.0.0.1"
        ];
        rpcallowip = [
          "127.0.0.1"
        ] ++ lib.lists.concatMap (s: [
          "${netns.${s}.address}"
        ]) netns.bitcoind.availableNetns;
      };

    })
    # Custom netns config option values if netns-isolation not enabled
    (mkIf (!cfg.enable) {
    })
  ];
}