# Nodeinfo
Run `nodeinfo` to see onion addresses and local addresses for enabled services.

# Managing services

NixOS uses the [systemd](https://wiki.archlinux.org/title/systemd) service manager.

Usage:
```shell
# Show service status
systemctl status bitcoind

# Show the last 100 log messages
journalctl -u bitcoind -n 100
# Show all log messages since the last system boot
journalctl -b -u bitcoind

# These commands require root permissions
systemctl stop bitcoind
systemctl start bitcoind
systemctl restart bitcoind

# Show the service definition
systemctl cat bitcoind
# Show all service parameters
systemctl show bitcoind
```

# Setup clightning database replication

Clightning can write an additional, replica database to a SSHFS (remote
filesystem over SSH) destination or a local directory path. The local directory
can also be used to write to custom targets mounted at that path, like external
HDD's, or NFS/SMB shares. Backups can also be automatically encrypted using
gocryptfs.

Note: You should also backup `hsm_secret` (located at
`/var/lib/clightning/bitcoin/hsm_secret` in most cases) separately, manually
and/or using the `services.backups` module.

## SSHFS

1. Append to your `configuration.nix`

    ```
    services.clightning.replication = {
      enable = true;
      sshfs.destination = "user@hostname:directory";
      encrypt = true;
    };
    programs.ssh.knownHosts."hostname".publicKey = "<ssh public key from running `ssh-keyscan` on the host>";
    ```

    Leave out the `encrypt` line if you want to store data on your destination
    in plaintext.

2. Deploy new `configuration.nix`

3. Authorize the public key on your destination by copying the contents of
   `$secretsDir/clightning-replication-ssh.pub` to the `authorized_keys` file of
   `user` or by using `ssh-copy-id`.

4. You can restrict the nix-bitcoin node's capabilities on the SSHFS target
   using OpenSSH's builtin features, as detailed
   [here](https://serverfault.com/questions/354615/allow-sftp-but-disallow-ssh).

   To easily get this working on NixOS, you should add the following to the
   SSHFS target's configuration:

    ```
    systemd.tmpfiles.rules = [
      "d '/var/backup/<user>' 0755 root root - -"
      "d '/var/backup/<user>/writeable' 0700 <user> sftponly - -"
    ];

    services.openssh = {
      extraConfig = ''
        Match group sftponly
          ChrootDirectory /var/backup/%u
          X11Forwarding no
          AllowTcpForwarding no
          AllowAgentForwarding no
          ForceCommand internal-sftp
      '';
    };

    users.groups.sftponly = {};
    users.users.<user> = {
      shell = "${pkgs.coreutils}/bin/false";
      extraGroups = [ "sftponly" ];
    };
    ```

## Local Directory

1. Append to your `configuration.nix`

    ```
    services.clightning.replication = {
      enable = true;
      local.directory = "/var/backup/clightning";
      encrypt = true;
    };
    ```

    Leave out the `encrypt` line if you want to store data in your
    `local.directory` in plaintext.

2. Deploy new `configuration.nix`

clightning will now replicate database files locally to `local.directory`. This
can be used to replicate to an external HDD by mounting it at path
`local.directory`.

## Custom remote destination

Follow the steps in section "Local Directory" above and mount a custom remote
destination (for example NFS or SMB share) to `local.directory`. You might want
to disable `local.setupDirectory` in order to create the mount directory
yourself with custom permissions.

# Connect to RTL
Normally you would connect to RTL via SSH tunneling with a command like this

```
ssh -L 3000:localhost:3000 root@bitcoin-node
```

Or like this, if you are using `netns-isolation`

```
ssh -L 3000:169.254.1.29:3000 root@bitcoin-node
```

Otherwise, you can access it via Tor Browser at `http://<onion-address>`.
You can find the `<onion-address>` with command `nodeinfo`.
The default password location is `$secretsDir/rtl-password`.
See: [Secrets dir](./configuration.md#secrets-dir)

# Use LND or clightning with Zeus (mobile wallet) via Tor
1. Install [Zeus](https://zeusln.app)

2. Edit your `configuration.nix`

   ##### For lnd

   Add the following config:
   ```
   services.lnd.lndconnectOnion.enable = true;
   ```

   ##### For clightning

   Add the following config:
   ```
   services.clightning-rest = {
     enable = true;
     lndconnectOnion.enable = true;
   };
   ```

3. Deploy your configuration

3. Run the following command on your node (as user `operator`) to create a QR code
   with address and authentication information:

   ##### For lnd
   ```
   lndconnect-onion
   ```

   ##### For clightning
   ```
   lndconnect-onion-clightning
   ```

4. Configure Zeus
   - Add a new node
   - Select `Scan lndconnect config` (at the bottom) and scan the QR code
   - For clightning: Set `Node interface` to `c-lightning-REST`
   - Click `Save node config`
   - Start sending and stacking sats privately

### Additional lndconnect features
Create plain text URLs or QR code images:
```
lndconnect-onion --url
lndconnect-onion --image
``````
Create a QR code for a custom hostname:
```
lndconnect-onion --host=mynode.org
```

# Connect to spark-wallet
### Requirements
* Android phone
* [Orbot](https://guardianproject.info/apps/orbot/) installed from [F-Droid](https://guardianproject.info/fdroid) (recommended) or [Google Play](https://play.google.com/store/apps/details?id=org.torproject.android&hl=en)
* [Spark-wallet](https://github.com/shesek/spark-wallet) installed from [direct download](https://github.com/shesek/spark-wallet/releases) or [Google Play](https://play.google.com/store/apps/details?id=com.spark.wallet)

1. Enable spark-wallet in `configuration.nix`

    Change
    ```
    # services.spark-wallet.enable = true;
    ```
    to
    ```
    services.spark-wallet.enable = true;
    ```

2. Deploy new `configuration.nix`

3. Enable Orbot VPN for spark-wallet

    ```
    Open Orbot app
    Turn on "VPN Mode"
    Select Gear icon under "Tor-Enabled Apps"
    Toggle checkbox under Spark icon
    ```

4. Get the onion address, access key and QR access code for the spark wallet android app

    ```
    journalctl -eu spark-wallet
    ```
    Note: The qr code might have issues scanning if you have a light terminal theme. Try setting it to dark or highlighting the entire output to invert the colors.

5. Connect to spark-wallet android app

    ```
    Server Settings
    Scan QR
    Done
    ```

# Connect to electrs
### Requirements Android
* Android phone
* [Orbot](https://guardianproject.info/apps/orbot/) installed from [F-Droid](https://guardianproject.info/fdroid) (recommended) or [Google Play](https://play.google.com/store/apps/details?id=org.torproject.android&hl=en)
* [Electrum mobile app](https://electrum.org/#home) 4.0.1 and newer installed from [direct download](https://electrum.org/#download) or [Google Play](https://play.google.com/store/apps/details?id=org.electrum.electrum)

### Requirements Desktop
* [Tor](https://www.torproject.org/) installed from [source](https://www.torproject.org/docs/tor-doc-unix.html.en) or [repository](https://www.torproject.org/docs/debian.html.en)
* [Electrum](https://electrum.org/#download) installed

1. Enable electrs in `configuration.nix`

    Change
    ```
    # services.electrs.enable = true;
    ```
    to
    ```
    services.electrs.enable = true;
    ```

2. Deploy new `configuration.nix`

3. Get electrs onion address with format `<onion-address>:<port>`

    ```
    nodeinfo | jq -r .electrs.onion_address
    ```

4. Connect to electrs

    Make sure Tor is running on Desktop or as Orbot on Android.

    On Desktop
    ```
    electrum --oneserver -1 -s "<electrs onion address>:t" -p socks5:localhost:9050
    ```

    On Android
    ```
    Three dots in the upper-right-hand corner
    Network > Proxy mode: socks5, Host: 127.0.0.1, Port: 9050
    Network > Auto-connect: OFF
    Network > One-server mode: ON
    Network > Server: <electrs onion address>:t
    ```

# Connect to nix-bitcoin node through the SSH onion service
1. Get the SSH onion address (excluding the port suffix)

    ```
    ssh operator@bitcoin-node
    nodeinfo | jq -r .sshd.onion_address | sed 's/:.*//'
    ```

2. Create a SSH key

    ```
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
    ```

3. Place the ed25519 key's fingerprint in the `configuration.nix` `openssh.authorizedKeys.keys` field like so

    ```
    # FIXME: Add your SSH pubkey
    services.openssh.enable = true;
    users.users.root = {
      openssh.authorizedKeys.keys = [ "<contents of ~/.ssh/id_ed25519.pub>" ];
    };
    ```

4. Connect to your nix-bitcoin node's SSH onion service, forwarding a local port to the nix-bitcoin node's SSH server

    ```
    ssh -i ~/.ssh/id_ed25519 -L <random port of your choosing>:localhost:22 root@<SSH onion address>
    ```

5. Edit your deployment tool's configuration and change the node's address to `localhost` and the ssh port to `<random port of your choosing>`.
   If you use krops as described in the [installation tutorial](./install.md), set `target = "localhost:<random port of your choosing>";` in `krops/deploy.nix`.


6. After deploying the new configuration, it will connect through the SSH tunnel you established in step iv. This also allows you to do more complex SSH setups that some deployment tools don't support. An example would be authenticating with [Trezor's SSH agent](https://github.com/romanz/trezor-agent), which provides extra security.

# Initialize a Trezor for Bitcoin Core's Hardware Wallet Interface

1. Enable Trezor in `configuration.nix`

    Change
    ```
    # services.hardware-wallets.trezor = true;
    ```
    to
    ```
    services.hardware-wallets.trezor = true;
    ```

2. Deploy new `configuration.nix`

3. Check that your nix-bitcoin node recognizes your Trezor

    ```
    ssh operator@bitcoin-node
    lsusb
    ```
    Should show something relating to your Trezor

4. If your Trezor has outdated firmware or is not yet initialized: Start your Trezor in bootloader mode

    Trezor v1
    ```
    Plug in your Trezor with both buttons depressed
    ```

    Trezor v2
    ```
    Start swiping your finger across your Trezor's touchscreen and plug in the USB cable when your finger is halfway through
    ```

5. If your Trezor's firmware is outdated: Update your Trezor's firmware

    ```
    trezorctl firmware-update
    ```
    Follow the on-screen instructions

    **Caution: This command _will_ wipe your Trezor. If you already store Bitcoin on it, only do this with the recovery seed nearby.**

6. If your Trezor is not yet initialized: Set up your Trezor

    ```
    trezorctl reset-device -p
    ```
    Follow the on-screen instructions

7. Find your Trezor

    ```
    hwi enumerate
    hwi -t trezor -d <path from previous command> promptpin
    hwi -t trezor -d <path> sendpin <number positions for the PIN as displayed on your device's screen>
    hwi enumerate
    ```

8. Follow Bitcoin Core's instructions on [Using Bitcoin Core with Hardware Wallets](https://github.com/bitcoin-core/HWI/blob/master/docs/bitcoin-core-usage.md) to use your Trezor with `bitcoin-cli` on your nix-bitcoin node

# JoinMarket

## Diff to regular JoinMarket usage

For clarity reasons, nix-bitcoin renames all scripts to `jm-*` without `.py`, for
example `wallet-tool.py` becomes `jm-wallet-tool`. The rest of this section
details nix-bitcoin specific workflows for JoinMarket.

## Wallets

By default, a wallet is automatically generated at service startup.
It's stored at `/var/lib/joinmarket/wallets/wallet.jmdat`, and its mnmenoic recovery
seed phrase is stored at `/var/lib/joinmarket/jm-wallet-seed`.

A missing wallet file is automatically recreated if the seed file is still present.

If you want to manually initialize your wallet instead, follow these steps:

1. Enable JoinMarket in your node configuration

    ```
    services.joinmarket.enable = true;
    ```

2. Move the automatically generated `wallet.jmdat`

    ```console
    mv /var/lib/joinmarket/wallet.jmdat /var/lib/joinmarket/bak.jmdat
    ```

3. Generate wallet on your node

    ```console
    jm-wallet-tool generate
    ```
    Follow the on-screen instructions and write down your seed.

    In order to use nix-bitcoin's `joinmarket.yieldgenerator`, use the password
    from `$secretsDir/jm-wallet-password` and use the suggested default wallet name
    `wallet.jmdat`. If you want to use your own `jm-wallet-password`, simply
    replace the password string in your local secrets directory.
    See: [Secrets dir](./configuration.md#secrets-dir)

## Run the tumbler

The tumbler needs to be able to run in the background for a long time, use screen
to run it accross SSH sessions. You can also use tmux in the same fashion.

1. Add screen to your `environment.systemPackages`, for example

    ```
    environment.systemPackages = with pkgs; [
      vim
      screen
    ];
    ```

2. Start the screen session

    ```console
    screen -S "tumbler"
    ```

3. Start the tumbler

    Example: Tumbling into your wallet after buying from an exchange to improve privacy:

    ```console
    jm-tumbler wallet.jmdat <addr1> <addr2> <addr3>
    ```

    After tumbling your bitcoin end up in these three addresses. You can now
    spend them without the exchange collecting data on your purchases.

    Get more information [here](https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/tumblerguide.md)

4. Detach the screen session to leave the tumbler running in the background

    ```
    Ctrl-a d or Ctrl-a Ctrl-d
    ```

5. Re-attach to the screen session

    ```console
    screen -r tumbler
    ```

6. End screen session

    Type exit when tumbler is done

    ```console
    exit
    ```

## Run a "maker" or "yield generator"

The maker/yield generator in nix-bitcoin is implemented using a systemd service.

See [here](https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/YIELDGENERATOR.md) for more yield generator information.

1. Enable yield generator bot in your node configuration

    ```
    services.joinmarket.yieldgenerator = {
      enable = true;
      # Optional: Add custom parameters
      txfee = 200;
      cjfee_a = 300;
    };
    '';
    ```

2. Check service status

    ```console
    systemctl status joinmarket-yieldgenerator
    ```

3. Profit

# clightning

## Plugins
There is a number of [plugins](https://github.com/lightningd/plugins) available for clightning.
See [`Readme: Features → clightning`](../README.md#features) or [search.nixos.org][1] for a complete list.

[1]: https://search.nixos.org/flakes?channel=unstable&from=0&size=30&sort=relevance&type=options&query=services.clightning.plugins

You can activate and configure these plugins like so:

```nix
services.clightning = {
    enable = true;
    plugins = {
        prometheus.enable = true;
        prometheus.listen = "0.0.0.0:9900";
    };
};
```

Please have a look at the module for a plugin (e.g. [prometheus.nix](../modules/clightning-plugins/prometheus.nix)) to learn its configuration options.
