Preliminary steps
---
Get a machine to deploy nix-bitcoin on.
This could be a VirtualBox, a machine that is already running [NixOS](https://nixos.org/nixos/manual/index.html) or a cloud provider.
Have a look at the options in the [NixOps manual](https://nixos.org/nixops/manual/).

# Tutorials
1. [Install and configure NixOS for nix-bitcoin on VirtualBox](#tutorial-install-and-configure-nixos-for-nix-bitcoin-on-virtualbox)
2. [Install and configure NixOS for nix-bitcoin on VirtualBox (macOS host)](#tutorial-install-and-configure-nixos-for-nix-bitcoin-on-virtualbox-macOS-host)
3. [Install and configure NixOS for nix-bitcoin on your own hardware](#tutorial-install-and-configure-nixos-for-nix-bitcoin-on-your-own-hardware)

----

Tutorial: install and configure NixOS for nix-bitcoin on VirtualBox
---
## 1. VirtualBox installation
The following steps are meant to be run on the machine you deploy from, not the machine you deploy to.

1. Add virtualbox.list to /etc/apt/sources.list.d (Debian 9 stretch)

	```
	echo "deb http://download.virtualbox.org/virtualbox/debian stretch contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
	```

2. Add Oracle VirtualBox public key

	```
	wget https://www.virtualbox.org/download/oracle_vbox_2016.asc
	gpg2 oracle_vbox_2016.asc
	```

	Proceed _only_ if fingerprint reads B9F8 D658 297A F3EF C18D  5CDF A2F6 83C5 2980 AECF

	```
	sudo apt-key add oracle_vbox_2016.asc
	```

3. Install virtualbox-5.2

	```
	sudo apt-get update
	sudo apt-get install virtualbox-5.2
	```

3. Create Host Adapter in VirtualBox

	```
	vboxmanage hostonlyif create
	```

## 2. Nix installation
The following steps are meant to be run on the machine you deploy from, not the machine you deploy to.
You can also build Nix from source by following the instructions at https://nixos.org/nix/manual/#ch-installing-source.

1. Install Dependencies (Debian 9 stretch)

	```
	sudo apt-get install curl git gnupg2 dirmngr
	```

2. Install latest Nix in "multi-user mode" with GPG Verification

	```
	curl -o install-nix https://nixos.org/nix/install
	curl -o install-nix.sig https://nixos.org/nix/install.sig
	gpg2 --recv-keys B541D55301270E0BCF15CA5D8170B4726D7198DE
	gpg2 --verify ./install-nix.sig
	sh ./install-nix --daemon
	```

	Then follow the instructions. Open a new terminal window when you're done.

	If you get an error similar to
	```
	error: cloning builder process: Operation not permitted
	error: unable to start build process
	/tmp/nix-binary-tarball-unpack.hqawN4uSPr/unpack/nix-2.2.1-x86_64-linux/install: unable to install Nix into your default profile
	```
	you're likely not installing as multi-user because you forgot to pass the `--daemon` flag to the install script.

3. Optional: Disallow substitutes

	You can put `substitute = false` to your `nix.conf` usually found in `/etc/nix/` to build the packages from source.
	This eliminates an attack vector where nix's build server or binary cache is compromised.


## 3. Nixops deployment

1. Clone this project

	```
	cd
	git clone https://github.com/fort-nix/nix-bitcoin
	cd ~/nix-bitcoin
	```

2. Setup environment

	```
	nix-shell
	```

	This will set up your nix-bitcoin environment and might take a while without giving an output.

3. Create nixops deployment in nix-shell.

	```
	nixops create network/network.nix network/network-vbox.nix -d bitcoin-node
	```

4. Adjust configuration by opening `configuration.nix` and removing FIXMEs. Enable/disable the modules you want in `configuration.nix`.

5. Deploy Nixops in nix-shell

	```
	nixops deploy -d bitcoin-node
	```

	This will now create a nix-bitcoin node on the target machine.

6. Nixops automatically creates an ssh key for use with `nixops ssh`. Access `bitcoin-node` through ssh in nix-shell with

	```
	nixops ssh operator@bitcoin-node
	```

See [usage.md](usage.md) for usage instructions, such as how to update.

To resize the VM disk image, you can use this helper script from within nix-shell:
```
./helper/vbox-resize-disk1.sh --help
```
----

Tutorial: install and configure NixOS for nix-bitcoin on VirtualBox (macOS host)
---
## 1. VirtualBox installation (macOS)
The following steps are meant to be run on the machine you deploy from, not the machine you deploy to.

1. Download and install VirtualBox
	Use the official Downloads page: [https://www.virtualbox.org/wiki/Downloads](https://www.virtualbox.org/wiki/Downloads)

	Make sure that the installer you download shows a lock icon in the top right corner to make sure it is signed by Oracle.

2. Create Host Adapter in VirtualBox

	```
	vboxmanage hostonlyif create
	```

## 2. Nix installation (macOS)

Follow the instructions from [Nix installation on debian](#2-nix-installation). You will may need to replace `gpg2` with `gpg`.

## 3. LinuxKit Nix installation
In order to build binaries for your linux (NixOS) virtual machine on a macOS host machine, you need to use [linuxkit-nix](https://github.com/nix-community/linuxkit-nix). It uses hyperkit to spin up a separate VM on which it builds binaries. An alternative solution is [nix-docker-build-slave](https://github.com/LnL7/nix-docker/blob/master/start-docker-nix-build-slave).

1. Installation

	```
	nix-env -i /nix/store/jgq3savsyyrpsxvjlrz41nx09z7r0lch-linuxkit-builder
    nix-linuxkit-configure
	```

	You may want to use `nix-linuxkit-configure -c 4` to give the builder 4 CPUs.

2. Confirm that nix-linuxkit works

    ```
	nix-build ~/.cache/nix-linuxkit-builder/example.nix
	```

	As the installer says, run a `nix-build` to make sure that you are able to build linux binaries. The `example.nix` is specifically configured to force a x86_64-linux build. Remove the generated `result` folder afterwards.

## 4. Nixops deployment (macOS)

Follow the instructions from [Nixops deployment on debian](#3-nixops-deployment). Add  `--option system x86_64-linux` to the `nixops deploy` command in step 5 to force your system to use linuxkit-nix.

----

Tutorial: install and configure NixOS for nix-bitcoin on your own hardware
---

## 0. Preparation

1. Optional: Make sure you have the latest firmware for your system (BIOS, microcode updates).

2. Optional: Disable Simultaneous Multi-Threading (SMT) in the BIOS

    Researchers recommend disabling (SMT), also known as Hyper-Threading Technology in the Intel® world to significantly reduce the impact of speculative execution-based attacks (https://mdsattacks.com/).

## 1. NixOS installation

This is borrowed from the [NixOS manual](https://nixos.org/nixos/manual/index.html#ch-installation). Look there for more information.

1. Obtain latest [NixOS](https://nixos.org/nixos/download.html). For example:

	```
	wget https://releases.nixos.org/nixos/19.09/nixos-19.09.2284.bf7c0f0461e/nixos-minimal-19.09.2284.bf7c0f0461e-x86_64-linux.iso
	sha256sum nixos-minimal-19.09.2284.bf7c0f0461e-x86_64-linux.iso
	9768eb945bef410fccfb82cb3d2e7ce7c02c3430aed0f2f1527273cb080fff3e
	```
	Alternatively you can build NixOS from source by following the instructions at https://nixos.org/nixos/manual/index.html#sec-building-cd.

2. Write NixOS iso to install media (USB/CD). For example:

	```
	dd if=nixos-minimal-19.09.2284.bf7c0f0461e-x86_64-linux.iso of=/dev/sdX
	```

	Replace /dev/sdX with the correct device name. You can find this using `sudo fdisk -l`

3. Boot the system

	You will have to find out if your hardware uses UEFI or Legacy Boot for the next step.

4. Option 1: Partition and format for UEFI

	```
	parted /dev/sda -- mklabel gpt
	parted /dev/sda -- mkpart primary 512MiB -8GiB
	parted /dev/sda -- mkpart primary linux-swap -8GiB 100%
	parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
	parted /dev/sda -- set 3 boot on
	mkfs.ext4 -L nixos /dev/sda1
	mkswap -L swap /dev/sda2
	mkfs.fat -F 32 -n boot /dev/sda3
	mount /dev/disk/by-label/nixos /mnt
	mkdir -p /mnt/boot
	mount /dev/disk/by-label/boot /mnt/boot
	swapon /dev/sda2
	```

4. Option 2: Partition and format for Legacy Boot (MBR)

	```
	parted /dev/sda -- mklabel msdos
	parted /dev/sda -- mkpart primary 1MiB -8GiB
	parted /dev/sda -- mkpart primary linux-swap -8GiB 100%
	mkfs.ext4 -L nixos /dev/sda1
	mkswap -L swap /dev/sda2
	mount /dev/disk/by-label/nixos /mnt
	swapon /dev/sda2
	```

4. Option 3: Set up encrypted partitions:

    Follow the guide at https://gist.github.com/martijnvermaat/76f2e24d0239470dd71050358b4d5134.

5. Generate NixOS config

	```
	nixos-generate-config --root /mnt
	nano /mnt/etc/nixos/configuration.nix
	```

	Option 1: Edit NixOS configuration for UEFI

	```
	{ config, pkgs, ... }: {
	  imports = [
	    # Include the results of the hardware scan.
	    ./hardware-configuration.nix
	  ];

	  boot.loader.systemd-boot.enable = true;

	  # Note: setting fileSystems is generally not
	  # necessary, since nixos-generate-config figures them out
	  # automatically in hardware-configuration.nix.
	  #fileSystems."/".device = "/dev/disk/by-label/nixos";
	
	  # Enable the OpenSSH server.
	  services.openssh = {
	    enable = true;
	    permitRootLogin = "yes";
	  };
	}
	```

	Option 2: Edit NixOS configuration for Legacy Boot (MBR)

	```
	{ config, pkgs, ... }: {
	  imports = [
	    # Include the results of the hardware scan.
	    ./hardware-configuration.nix
	  ];
	
	  boot.loader.grub.device = "/dev/sda"; 
	
	  # Note: setting fileSystems is generally not
	  # necessary, since nixos-generate-config figures them out
	  # automatically in hardware-configuration.nix.
	  #fileSystems."/".device = "/dev/disk/by-label/nixos";
	
	  # Enable the OpenSSH server.
	  services.openssh = {
	    enable = true;
	    permitRootLogin = "yes";
	  };
	}
	```

6. Do the installation

	```
	nixos-install
	```
	Set root password
	```
	setting root password...
	Enter new UNIX password: 
	Retype new UNIX password:
	```

7. If everything went well

	```
	reboot
	```

## 2. nix-bitcoin installation

On the machine you are deploying from:
You can also build Nix from source by following the instructions at https://nixos.org/nix/manual/#ch-installing-source.

1. Install Dependencies (Debian 9 stretch)

	```
	sudo apt-get install curl git gnupg2 dirmngr
	```

2. Install Latest Nix with GPG Verification

	```
	curl -o install-nix https://nixos.org/nix/install
	curl -o install-nix.sig https://nixos.org/nix/install.sig
	gpg2 --recv-keys B541D55301270E0BCF15CA5D8170B4726D7198DE
	gpg2 --verify ./install-nix.sig
	sh ./install-nix --daemon
	. /home/user/.nix-profile/etc/profile.d/nix.sh
	```

	Then follow the instructions. Open a new terminal window when you're done.

	If you get an error similar to
	```
	error: cloning builder process: Operation not permitted
	error: unable to start build process
	/tmp/nix-binary-tarball-unpack.hqawN4uSPr/unpack/nix-2.2.1-x86_64-linux/install: unable to install Nix into your default profile
	```
	you're likely not installing as multi-user because you forgot to pass the `--daemon` flag to the install script.

3. Optional: Disallow substitutes

	You can put `substitute = false` to your `nix.conf` usually found in `/etc/nix/` to build the packages from source.
	This eliminates an attack vector where nix's build server or binary cache is compromised.

4. Clone this project

	```
	cd
	git clone https://github.com/fort-nix/nix-bitcoin
	cd ~/nix-bitcoin
	```

5. Create network file

	```
	nano network/network-nixos.nix
	```

	```
	{
	  bitcoin-node =
	    { config, pkgs, ... }:
	    { deployment.targetHost = "1.2.3.4";
	    };
	}
	```

	Replace 1.2.3.4 with NixOS machine's IP address.

6. Edit `configuration.nix`

	```
	nano configuration.nix
	```

	Uncomment `./hardware-configuration.nix` line by removing #.

7. Create `hardware-configuration.nix`

	```
	nano hardware-configuration.nix
	```
	Copy contents of NixOS machine's `/etc/nixos/hardware-configuration.nix` to file.

8. Add boot option to `hardware-configuration.nix`

	Option 1: Enable systemd boot for UEFI
	```
	boot.loader.grub.device = "/dev/sda";
	```
	Option 2: Set grub device for Legacy Boot (MBR)
	```
	boot.loader.grub.device = "/dev/sda";
	```

9. Setup environment

	```
	nix-shell
	```

	This will set up your nix-bitcoin environment and might take a while without giving an output.

10. Create nixops deployment in nix-shell.

	```
	nixops create network/network.nix network/network-nixos.nix -d bitcoin-node
	```

11. Adjust configuration by opening `configuration.nix` and removing FIXMEs. Enable/disable the modules you want in `configuration.nix`.

12. Deploy Nixops in nix-shell

	```
	nixops deploy -d bitcoin-node
	```

	This will now create a nix-bitcoin node on the target machine.

13. Nixops automatically creates an ssh key for use with `nixops ssh`. Access `bitcoin-node` through ssh in nix-shell with

	```
	nixops ssh operator@bitcoin-node
	```

See [usage.md](usage.md) for usage instructions, such as how to update.
