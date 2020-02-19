{
  bitcoin-node =
    { config, pkgs, ... }:
    {
      deployment.targetEnv = "virtualbox";
      deployment.virtualbox = {
        memorySize = 4096; # megabytes
        vcpu = 4; # number of cpus
        disks.disk1.size = 358400; # 350 GiB
        headless = true;
      };
    };
}
