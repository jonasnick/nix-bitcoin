{ config, lib, pkgs, ... }:

with lib;
let
  options.services.clightning.replication = {
    enable =  mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable live replication of the clightning database.
        This prevents losing off-chain funds when the primary wallet file becomes
        inaccessible.

        For setting the destination, you can either define option `sshfs.destination`
        or `local.directory`.

        When `encrypt` is `false`, file `lightningd.sqlite3` is written to the destination.
        When `encrypt` is `true`, directory `lightningd-db` is written to the destination.
        It includes the encrypted database and gocryptfs metadata.

        See also: https://github.com/ElementsProject/lightning/blob/master/doc/BACKUP.md
      '';
    };
    sshfs = {
      destination = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "user@10.0.0.1:directory";
        description = ''
          The SSH destination for which a SSHFS will be mounted.
          `directory` is relative to the home of `user`.

          A SSH key is automatically generated and stored in file
          `$secretsDir/clightning-replication-ssh`.
          The SSH server must allow logins via this key.
          I.e., the `authorized_keys` file of `user` must contain
          `$secretsDir/clightning-replication-ssh.pub`.
        '';
      };
      port = mkOption {
        type = types.port;
        default = 22;
        description = "SSH port of the remote server.";
      };
      sshOptions = mkOption {
        type = with types; listOf str;
        default = [ "reconnect" "ServerAliveInterval=50" ];
        description = "SSH options used for mounting the SSHFS.";
      };
    };
    local = {
      directory = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/var/backup/clightning";
        description = ''
          This option can be specified instead of `sshfs.destination` to enable
          replication to a local directory.

          If `local.setupDirectory` is disabled, the directory
            - must already exist when `clightning.service` (or `clightning-replication-mounts.service`
              if `encrypt` is `true`) starts.
            - must have write permissions for the `clightning` user.

          This option is also useful if you want to use a custom remote destination,
          like a NFS or SMB share.
        '';
      };
      setupDirectory = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Create `local.directory` if it doesn't exist and set write permissions
          for the `clightning` user.
        '';
      };
    };
    encrypt = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to encrypt the replicated database with gocryptfs.
        The encryption password is automatically generated and stored
        in file `$secretsDir/clightning-replication-password`.
      '';
    };
  };

  cfg = config.services.clightning.replication;
  inherit (config.services) clightning;

  secretsDir = config.nix-bitcoin.secretsDir;
  network = config.services.bitcoind.makeNetworkName "bitcoin" "regtest";
  user = clightning.user;
  group = clightning.group;

  useSshfs = cfg.sshfs.destination != null;
  useMounts = useSshfs || cfg.encrypt;

  localDir = cfg.local.directory;
  mountsDir = "/var/lib/clightning-replication";
  sshfsDir = "${mountsDir}/sshfs";
  plaintextDir = "${mountsDir}/plaintext";
  destDir =
    if cfg.encrypt then
      plaintextDir
    else if useSshfs then
      sshfsDir
    else
      localDir;
in {
  inherit options;

  config = mkIf cfg.enable {
    assertions = [
      { assertion = useSshfs || (localDir != null);
        message = ''
          services.clightning.replication: One of `sshfs.destination` or
          `local.directory` must be set.
        '';
      }
      { assertion = !useSshfs || (localDir == null);
        message = ''
          services.clightning.replication: Only one of `sshfs.destination` and
          `local.directory` must be set.
        '';
      }
    ];

    environment.systemPackages = optionals cfg.encrypt [ pkgs.gocryptfs ];

    systemd.tmpfiles.rules = optional (localDir != null && cfg.local.setupDirectory)
      "d '${localDir}' 0770 ${user} ${group} - -";

    services.clightning.wallet = let
      mainDB = "${clightning.dataDir}/${network}/lightningd.sqlite3";
      replicaDB = "${destDir}/lightningd.sqlite3";
    in "sqlite3://${mainDB}:${replicaDB}";

    systemd.services.clightning = {
      bindsTo = mkIf useMounts [ "clightning-replication-mounts.service" ];
      serviceConfig.ReadWritePaths = [
        # We can't simply set `destDir` here because it might point to
        # a FUSE mount.
        # FUSE mounts can only be set up as `ReadWritePaths` by systemd when they
        # are accessible by root. This would require FUSE-mounting with option
        # `allow_other`.
        (if useMounts then mountsDir else localDir)
      ];
    };

    systemd.services.clightning-replication-mounts = mkIf useMounts {
      requiredBy = [ "clightning.service" ];
      before = [ "clightning.service" ];
      after = [ "setup-secrets.service" ];
      path = [
        # Includes
        # - The SUID-wrapped `fusermount` binary which enables FUSE
        #   for non-root users
        # - The SUID-wrapped `mount` binary, used for unmounting
        "/run/wrappers"
      ] ++ optionals cfg.encrypt [
        # Includes `logger`, required by gocryptfs
        pkgs.util-linux
      ];

      script =
        optionalString useSshfs ''
          mkdir -p ${sshfsDir}
          ${pkgs.sshfs}/bin/sshfs ${cfg.sshfs.destination} -p ${toString cfg.sshfs.port} ${sshfsDir} \
            -o ${builtins.concatStringsSep "," ([
              "IdentityFile='${secretsDir}'/clightning-replication-ssh-key"
            ] ++ cfg.sshfs.sshOptions)}
        '' +
        optionalString cfg.encrypt ''
          cipherDir="${if useSshfs then sshfsDir else localDir}/lightningd-db"
          mkdir -p "$cipherDir" ${plaintextDir}
          gocryptfs=(${pkgs.gocryptfs}/bin/gocryptfs -passfile '${secretsDir}'/clightning-replication-password)
          # 1. init
          if [[ ! -e $cipherDir/gocryptfs.conf ]]; then
            "''${gocryptfs[@]}" -init "$cipherDir"
          fi
          # 2. mount
          "''${gocryptfs[@]}" "$cipherDir" ${plaintextDir}
        '';

      postStop =
        optionalString cfg.encrypt ''
          umount ${plaintextDir} || true
        '' +
        optionalString useSshfs ''
          umount ${sshfsDir}
        '';

      serviceConfig = {
        StateDirectory = "clightning-replication";
        StateDirectoryMode = "770";
        User = user;
        RemainAfterExit = "yes";
        Type = "oneshot";
      };
    };

    nix-bitcoin = mkMerge [
      (mkIf useSshfs {
        secrets.clightning-replication-ssh-key = {
          user = user;
          permissions = "0400";
        };
        generateSecretsCmds.clightning-replication-ssh-key = ''
          if [[ ! -f clightning-replication-ssh-key ]]; then
            ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -q -N "" -C "" -f clightning-replication-ssh-key
          fi
        '';
      })

      (mkIf cfg.encrypt {
        secrets.clightning-replication-password.user = user;
        generateSecretsCmds.clightning-replication-password = ''
          makePasswordSecret clightning-replication-password
        '';
      })
    ];
  };
}
