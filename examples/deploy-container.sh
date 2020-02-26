#!/usr/bin/env bash
set -euo pipefail

# This script demonstrates how to setup a nix-bitcoin node in a NixOS container.
# Running this script leaves no traces on your host system.

# This demo is a template for your own experiments.
# Feel free to modify or to run nix-shell and execute individual statements of this
# script in the interactive shell.

if [[ $(sysctl -n net.ipv4.ip_forward) != 1 ]]; then
    echo "Error: IP forwarding (net.ipv4.ip_forward) is not enabled"
    exit 1
fi
if [[ ! -e /run/current-system/nixos-version ]]; then
    echo "Error: This script needs NixOS to run"
    exit 1
fi

if [[ ! -v IN_NIX_SHELL ]]; then
    echo "Running script in nix shell env..."
    exec nix-shell --run "${BASH_SOURCE[0]}"
fi

# Build container.
# You can re-run this command with a changed container config.
# The running container is then switched to the new config.
# Learn more: https://github.com/erikarvstedt/extra-container
#
sudo extra-container create --start <<'EOF'
{ pkgs, lib, ... }: let
    containerName = "demo-node"; # container name length is limited to 11 chars
    localAddress = "10.250.0.2"; # container address
    hostAddress = "10.250.0.1";
in {
  containers.${containerName} = {
    privateNetwork = true;
    inherit localAddress hostAddress;
    config = { pkgs, config, lib, ... }: {
      imports = [
        <nix-bitcoin/example/configuration.nix>
        <nix-bitcoin/modules/secrets/generate-secrets.nix>
      ];
      # Speed up evaluation
      documentation.nixos.enable = false;
    };
  };
  # Allow WAN access
  systemd.services."container@${containerName}" = {
    preStart = "${pkgs.iptables}/bin/iptables -w -t nat -A POSTROUTING -s ${localAddress} -j MASQUERADE";
    # Delete rule
    postStop = "${pkgs.iptables}/bin/iptables -w -t nat -D POSTROUTING -s ${localAddress} -j MASQUERADE || true";
  };
}
EOF
# Run command in container
c() { sudo extra-container run demo-node -- "$@" | cat; }

echo
echo "Service info:"
c systemctl status bitcoind
c bitcoin-cli getnetworkinfo
c lightning-cli getinfo
c nodeinfo

echo
echo "Bitcoind data dir:"
sudo ls -al /var/lib/containers/demo-node/var/lib/bitcoind

echo
echo "Deleting container..."
sudo extra-container destroy demo-node
