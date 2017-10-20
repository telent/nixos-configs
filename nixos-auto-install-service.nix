{ config, pkgs, environment, ... }:

let installToHd = pkgs.writeScript "install-to-hd.sh" ''
#!${pkgs.bash}/bin/bash
PATH=/run/current-system/sw/bin:$PATH
set -ex
keyfile=/mnt/root/.ssh/authorized_keys

mkdir /mnt_key
mount -r /dev/vdb /mnt_key
cp /mnt_key/ssh.pub /tmp/root_ssh_key
umount /dev/vdb

parted /dev/vda mklabel msdos
parted /dev/vda -- mkpart primary ext4 1M -1s

# Format the partition
mkfs.ext4 -L nixos /dev/vda1
mkdir -p /mnt
mount /dev/vda1 /mnt

nixos-generate-config --root /mnt
sed -i 's/^.*grub.device.*$/ boot.loader.grub.device = "\/dev\/vda";/' /mnt/etc/nixos/configuration.nix
sed -i 's/^.*openssh.enable.*$/ services.openssh.enable = true;/' /mnt/etc/nixos/configuration.nix
mkdir -p /mnt/root/.ssh
chmod 700 /mnt/root/.ssh
cp /tmp/root_ssh_key /mnt/root/.ssh/authorized_keys 
nixos-install
umount /mnt
echo INSTALL_SUCCESSFUL >/dev/console
halt -p
    '';
in {
  boot.kernelParams = [ "console=ttyS0" ];
  systemd.services.install-to-hd = {
    enable = true;
    wantedBy = ["multi-user.target"];
    after = ["getty@tty1.service" ];
    environment = {
      NIX_PATH = "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos/nixpkgs:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [ installToHd ];
      StandardInput = "null";
      StandardOutput = "journal+console";
      StandardError = "inherit";
    };
  };

}
