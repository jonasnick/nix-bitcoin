#!/usr/bin/env bash
set -euo pipefail

# This script demonstrates how to setup a VirtualBox nix-bitcoin node with nixops.
# Running this script leaves no traces on your host system.

# This demo is a template for your own experiments.
# Feel free to modify or to run nix-shell and execute individual statements of this
# script in the interactive shell.

if [[ ! -v IN_NIX_SHELL ]]; then
    echo "Running script in nix shell env..."
    exec nix-shell --run "${BASH_SOURCE[0]}"
fi

# Cleanup on exit
cleanup() {
    set +e
    if nixops list | grep -q bitcoin-node; then
        nixops destroy --confirm -d bitcoin-node
    fi
    rm -rf $tmpDir
}
trap "cleanup" EXIT

tmpDir=/tmp/nix-bitcoin-nixops
mkdir -p $tmpDir

# Don't write nixops and VirtualBox data to the $USER's home
export HOME=$tmpDir

# Disable interactive queries and don't write to the $USER's known_hosts file
export NIXOPS_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

nixops create nixops/node.nix nixops/node-vbox.nix -d bitcoin-node
nixops deploy -d bitcoin-node

# Connect to node
nixops ssh bitcoin-node systemctl status bitcoind

# Cleanup happens at exit (see above)
