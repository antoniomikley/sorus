{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  boot = {
    initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci"  "sr_mod" "virtio_blk" ];
    kernelModules = [ "kvm-intel" ];
  };

  fileSystems = {
    "/" = {
      label = "NIXROOT";
      fsType = "ext4";
    };
    "/boot" = {
      label = "NIXBOOT";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };
  };
}
