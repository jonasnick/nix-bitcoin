<p align="center">
  <img
    width="320"
    src="docs/img/nix-bitcoin-logo.png"
    alt="nix-bitcoin logo">
</p>
<br/>
<p align="center">
    <a href="https://cirrus-ci.com/github/fort-nix/nix-bitcoin" target="_blank">
        <img src="https://api.cirrus-ci.com/github/fort-nix/nix-bitcoin.svg?branch=master" alt="CirrusCI status">
    </a>
    <a href="https://github.com/fort-nix/nix-bitcoin/releases/latest" target="_blank">
        <img src="https://img.shields.io/github/v/release/fort-nix/nix-bitcoin" alt="GitHub tag (latest SemVer)">
    </a>
    <a href="https://github.com/fort-nix/nix-bitcoin/commits/master" target="_blank">
        <img src="https://img.shields.io/github/commit-activity/y/fort-nix/nix-bitcoin" alt="GitHub commit activity">
    </a>
    <a href="https://github.com/fort-nix/nix-bitcoin/graphs/contributors" target="_blank">
        <img src="https://img.shields.io/github/contributors-anon/fort-nix/nix-bitcoin" alt="GitHub contributors">
    </a>
    <a href="https://github.com/fort-nix/nix-bitcoin/releases" target="_blank">
        <img src="https://img.shields.io/github/downloads/fort-nix/nix-bitcoin/total" alt="GitHub downloads">
    </a>
</p>
<br/>

nix-bitcoin is a collection of Nix packages and NixOS modules for easily installing **full-featured Bitcoin nodes** with an emphasis on **security**.

Overview
---
nix-bitcoin can be used for personal or merchant wallets, public infrastructure or
for Bitcoin application backends. In all cases, the aim is to provide security and
privacy by default. However, while nix-bitcoin is used in production today, it is
still considered experimental.

nix-bitcoin nodes can be deployed on dedicated hardware, virtual machines or containers.
The Nix packages and NixOS modules can be used independently and combined freely.

nix-bitcoin is built on top of Nix and [NixOS](https://nixos.org/) which provide powerful abstractions to keep it highly customizable and
maintainable. Testament to this are nix-bitcoin's robust security features and its potent test framework.  However,
running nix-bitcoin does not require any previous experience with the Nix ecosystem.

Get started
---
- See the [examples](examples/README.md) for an overview of all features.
- To setup a new node from scratch, see the [installation instructions](docs/install.md).
- To add nix-bitcoin to an existing NixOS configuration, see [importable-configuration.nix](examples/importable-configuration.nix)
  and the [Flake example](examples/flakes/flake.nix).

Docs
---
* [Hardware requirements](docs/hardware.md)
* [Installation](docs/install.md)
* [Configuration and maintenance](docs/configuration.md)
* [Using services](docs/services.md)
* [FAQ](docs/faq.md)

Features
---
A [configuration preset](modules/presets/secure-node.nix) for setting up a secure node
* All applications use Tor for outbound connections and support accepting inbound connections via onion services.

NixOS modules ([src](modules/modules.nix))
* Application services
  * [bitcoind](https://github.com/bitcoin/bitcoin), with a default banlist against spy nodes
  * [clightning](https://github.com/ElementsProject/lightning) with support for announcing an onion service\
    Available plugins:
    * [clboss](https://github.com/ZmnSCPxj/clboss): automated C-Lightning Node Manager
    * [helpme](https://github.com/lightningd/plugins/tree/master/helpme): walks you through setting up a fresh c-lightning node
    * [monitor](https://github.com/renepickhardt/plugins/tree/master/monitor): helps you analyze the health of your peers and channels
    * [prometheus](https://github.com/lightningd/plugins/tree/master/prometheus): lightning node exporter for the prometheus timeseries server
    * [rebalance](https://github.com/lightningd/plugins/tree/master/rebalance): keeps your channels balanced
    * [summary](https://github.com/lightningd/plugins/tree/master/summary): print a nice summary of the node status
    * [zmq](https://github.com/lightningd/plugins/tree/master/zmq): publishes notifications via ZeroMQ to configured endpoints
  * [lnd](https://github.com/lightningnetwork/lnd) with support for announcing an onion service and [static channel backups](https://github.com/lightningnetwork/lnd/blob/master/docs/recovery.md)
    * [Lightning Loop](https://github.com/lightninglabs/loop)
    * [Lightning Pool](https://github.com/lightninglabs/pool)
    * [charge-lnd](https://github.com/accumulator/charge-lnd): policy-based channel fee manager
    * [lndconnect](https://github.com/LN-Zap/lndconnect) via a REST onion service
  * [Ride The Lightning](https://github.com/Ride-The-Lightning/RTL): web interface for `lnd` and `clightning`
  * [spark-wallet](https://github.com/shesek/spark-wallet)
  * [electrs](https://github.com/romanz/electrs)
  * [btcpayserver](https://github.com/btcpayserver/btcpayserver)
  * [liquid](https://github.com/elementsproject/elements)
  * [JoinMarket](https://github.com/joinmarket-org/joinmarket-clientserver)
    * [JoinMarket Orderbook Watcher](https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/orderbook.md)
  * [bitcoin-core-hwi](https://github.com/bitcoin-core/HWI)
* Helper
  * [netns-isolation](modules/netns-isolation.nix): isolates applications on the network-level via network namespaces
  * [nodeinfo](modules/nodeinfo.nix): script which prints info about the node's services
  * [backups](modules/backups.nix): duplicity backups of all your node's important files
  * [operator](modules/operator.nix): adds non-root user `operator` who has access to client tools (e.g. `bitcoin-cli`, `lightning-cli`)

Security
---
See [SECURITY.md](SECURITY.md) for the security policy and how to report a vulnerability.

nix-bitcoin aims to achieve a high degree of security by building on the following principles:

* **Simplicity:** Only services enabled in `configuration.nix` and their dependencies are installed, support for [doas](https://github.com/Duncaen/OpenDoas) ([sudo alternative](https://lobste.rs/s/efsvqu/heap_based_buffer_overflow_sudo_cve_2021#c_c6fcfa)), code is continuously reviewed and refined.
* **Integrity:** The Nix package manager guarantees that all dependencies are exactly specified, packages can be built from source to reduce reliance on binary caches, nix-bitcoin merge commits are signed, all commits are approved by multiple nix-bitcoin developers, upstream packages are cryptographically verified where possible, we use this software ourselves.
* **Principle of Least Privilege:** Services operate with least privileges; they each have their own user and are restricted further with [systemd features](pkgs/lib.nix), [RPC whitelisting](modules/bitcoind-rpc-public-whitelist.nix) and [netns-isolation](modules/netns-isolation.nix). There's a non-root user *operator* to interact with the various services.
* **Defense-in-depth:** nix-bitcoin supports a [hardened kernel](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/hardened.nix), services are confined through discretionary access control, Linux namespaces, [dbus firewall](modules/security.nix) and seccomp-bpf with continuous improvements.

Note that if the machine you're deploying *from* is insecure, there is nothing nix-bitcoin can do to protect itself.

Troubleshooting
---
If you are having problems with nix-bitcoin check the [FAQ](docs/faq.md) or submit an issue.\
There's also a Matrix room at [#general:nixbitcoin.org](https://matrix.to/#/#general:nixbitcoin.org)
and a `#nix-bitcoin` IRC channel on [libera](https://libera.chat).\
We are always happy to help.
