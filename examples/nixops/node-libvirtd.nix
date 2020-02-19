{
  bitcoin-node =
    { config, pkgs, ... }:
    {
      deployment.targetEnv = "libvirtd";
      deployment.libvirtd.memorySize = 8192; # megabytes
      deployment.libvirtd.vcpu = 4; # number of cpus
      deployment.libvirtd.headless = true;
      deployment.libvirtd.baseImageSize = 400;
      boot.kernelParams = [ "console=ttyS0,115200" ];
      deployment.libvirtd.extraDevicesXML = ''
        <serial type='pty'>
          <target port='0'/>
       </serial>
        <console type='pty'>
          <target type='serial' port='0'/>
       </console>
      '';
      # Remove when fixed: https://github.com/NixOS/nixops/issues/931
      system.activationScripts.nixops-vm-fix-931 = {
        text = ''
          if ls -l /nix/store | grep sudo | grep -q nogroup; then
            mount -o remount,rw  /nix/store
            chown -R root:nixbld /nix/store
          fi
        '';
        deps = [];
      };
    };
}
