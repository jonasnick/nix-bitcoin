#!/usr/bin/env bash
set -euo pipefail

# This script demonstrates how to setup a nix-bitcoin node with krops.
# The node is deployed to a minimal NixOS QEMU VM.
# Running this script leaves no traces on your host system.

# This demo is a template for your own experiments.
# Run with option `--interactive` or `-i` to start a shell for interacting with
# the node.

# MAKE SURE TO REPLACE the SSH identity file if you use this script for
# anything serious.

if [[ ! -v IN_NIX_SHELL ]]; then
    echo "Running script in nix shell env..."
    cd "${BASH_SOURCE[0]%/*}"
    exec nix-shell --run "./${BASH_SOURCE[0]##*/} $*"
fi

source qemu-vm/run-vm.sh

echo "Building the target VM"
# Build the initial VM to which the nix-bitcoin node is deployed to via krops
nix-build --out-link $tmpDir/vm - <<'EOF'
(import <nixpkgs/nixos> {
  configuration = { lib, ... }: {
    imports = [ <qemu-vm/vm-config.nix>  ];
    services.openssh.enable = true;

    # Silence the following warning that appears when deploying via krops:
    # warning: Nix search path entry '/nix/var/nix/profiles/per-user/root/channels' does not exist, ignoring
    nix.nixPath = lib.mkForce [];
  };
}).vm
EOF

vmNumCPUs=4
vmMemoryMiB=2048
sshPort=60734
# Start the VM in the background
runVM $tmpDir/vm $vmNumCPUs $vmMemoryMiB $sshPort

# Build the krops deploy script
export sshPort
nix-build --out-link $tmpDir/krops-deploy - <<'EOF'
let
  krops = (import <nix-bitcoin> {}).krops;

  extraSources = {
    # Skip uploading nixpkgs to the target node.
    # This works because /nix/store is shared with the target VM.
    nixpkgs.symlink = toString <nixpkgs>;

    nixos-config.file = toString <krops-vm-configuration.nix>;

    qemu-vm.file = toString <qemu-vm>;
  };
in
krops.pkgs.krops.writeCommand "krops-deploy" {
  source = import <krops/sources.nix> { inherit extraSources krops; };
  force = true;
  target = {
    user = "root";
    host = "127.0.0.1";
    port = builtins.getEnv "sshPort";
    extraOptions = [
      "-i" (toString <qemu-vm/id-vm>) "-oConnectTimeout=1"
      "-oStrictHostKeyChecking=no" "-oUserKnownHostsFile=/dev/null" "-oLogLevel=ERROR"
      "-oControlMaster=auto" "-oControlPath=${builtins.getEnv "tmpDir"}/ssh-connection" "-oControlPersist=60"
    ];
  };

  # "test" instead of "switch" to avoid installing a bootloader which
  # is not possible in this VM
  command = targetPath: ''
    nixos-rebuild test -I /var/src
  '';
}
EOF

echo "Building the nix-bitcoin node"
# Pre-build the nix-bitcoin node outside of the VM to save some time
nix-build --out-link $tmpDir/store-paths -E '
let
  system = (import <nixpkgs/nixos> { configuration = <krops-vm-configuration.nix>; }).system;
  pkgsUnstable = (import <nix-bitcoin/pkgs/nixpkgs-pinned.nix>).nixpkgs-unstable;
  pkgs = import <nixpkgs> {};
in
  pkgs.closureInfo { rootPaths = [ system pkgsUnstable ]; }
' > /dev/null

vmWaitForSSH

# Add the store paths that include the nix-bitcoin node
# to the nix store db in the VM
c "nix-store --load-db < $(realpath $tmpDir/store-paths)/registration"

echo
echo "Deploy with krops"
$tmpDir/krops-deploy

echo
echo "Bitcoind service:"
c systemctl status bitcoind
echo
echo "Bitcoind network:"
c bitcoin-cli getnetworkinfo
echo
echo "lightning-cli state:"
c lightning-cli getinfo
echo
echo "Node info:"
c nodeinfo

case ${1:-} in
    -i|--interactive)
        . start-bash-session.sh
        ;;
esac

# Cleanup happens at exit (defined in qemu-vm/run-vm.sh)
