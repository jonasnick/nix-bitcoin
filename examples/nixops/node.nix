{
  network.description = "Bitcoin Core node";

  bitcoin-node =
    { config, pkgs, lib, ... }: {
      imports = [ ../configuration.nix <nix-bitcoin/modules/nix-bitcoin.nix> ];

      deployment.keys = builtins.mapAttrs (n: v: {
        keyFile = "${toString ../secrets}/${n}";
        destDir = config.nix-bitcoin.secretsDir;
        inherit (v) user group permissions;
      }) config.nix-bitcoin.secrets;

      # nixops makes the secrets directory accessible only for users with group 'key'.
      # For compatibility with other deployment methods besides nixops, we forego the
      # use of the 'key' group and make the secrets dir world-readable instead.
      # This is safe because all containing files have their specific private
      # permissions set.
      systemd.services.allowSecretsDirAccess = {
        requires = [ "keys.target" ];
        after = [ "keys.target" ];
        script = "chmod o+x ${config.nix-bitcoin.secretsDir}";
        serviceConfig.Type = "oneshot";
      };

      systemd.targets.nix-bitcoin-secrets = {
        requires = [ "allowSecretsDirAccess.service" ];
        after = [ "allowSecretsDirAccess.service" ];
      };
    };
}
