{ config, pkgs, lib, system ? builtins.currentSystem, ... }:

let hostNic =  "enp0s31f6";
    hostName = "loaclhost";
    pubkey = pkgs.writeText "guest-pubkey" "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDFYv/Cko02eYOqXJGKIlp75/LC1rYZeFarwSHS2XdYoFv57G4rEcN9O4mkOTVjQYmJV3+PhqAkAqJ5wOM35Ub55Bm0+sAnxcA4kzP1TFMMAmydMftXvOQr5G+FP24R+8CADz3R3Jr94vQ/vbQjV3lgb7vAg1i2MPadfadodKOkSkj9tDLPGf+iVTwVBv5p9QwCV1BOTFMfZQlPxBCtXAwY8ds9CLw5dDlnBd6+i44JP4M2FLlA1Qvm+nn6orYmz4GYMop9dx46T5DD+MBt6lnnJZXh+SUa5SIIq/7nNRrKH1H6EZwGvTld8Fwp1wxx6164UoM1/QNAimBUFhFdPyrH dan@carobn" ;
    iso = system: (import <nixpkgs/nixos/lib/eval-config.nix> {
      inherit system;
      modules = [
        <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
        ./nixos-auto-install-service.nix
      ];
      }).config.system.build.isoImage;
    firstRunScript = pkgs.writeScript "firstrun.sh" ''
#!${pkgs.bash}/bin/bash
hda=$1
size=$2
iso=$(echo /etc/nixos-cdrom.iso/nixos-*-linux.iso)
PATH=/run/current-system/sw/bin:$PATH
${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2  $hda.tmp $size
mkdir -p /tmp/keys
cp ${pubkey} /tmp/keys/ssh.pub
${pkgs.qemu_kvm}/bin/qemu-kvm -display vnc=127.0.0.1:99 -m 512 -drive file=$hda.tmp,if=virtio -drive file=fat:floppy:/tmp/keys,if=virtio,readonly -drive file=$iso,media=cdrom,readonly -boot order=d -serial stdio > $hda.console.log 
if grep INSTALL_SUCCESSFUL $hda.console.log ; then
  mv $hda.tmp $hda
fi
    '';
    guests = {
      bookshlv = {
        memory = "4g";
        diskSize = "40g";
        vncDisplay="localhost:1";
	netDevice="tap0";
      };
    };
in {
  options = {};
  config = {
    environment.etc."nixos-cdrom.iso".source =
      "${iso builtins.currentSystem}/iso/";

    # networking.bridges.vbridge0.interfaces = [hostNic]; 
    networking.interfaces = lib.foldl (m: g: m // {${g} = {virtual=true; virtualType="tap";};}) {} (map (g: g.netDevice) (builtins.attrValues guests));
    networking.bridges.vbridge0.interfaces = [hostNic] ++ (map (g: g.netDevice) (builtins.attrValues guests));

    systemd.services = lib.mapAttrs' (name: guest: lib.nameValuePair "qemu-guest-${name}" {
      wantedBy = [ "multi-user.target" ];
      script =
          ''
          disks=/var/lib/guests/disks/
          mkdir -p $disks
          hda=$disks/${name}.img
          if ! test -f $hda; then
            ${firstRunScript} $hda ${guest.diskSize}
          fi
          sock=/run/qemu-${name}.mon.sock
          ${pkgs.qemu_kvm}/bin/qemu-kvm -m ${guest.memory} -display vnc=${guest.vncDisplay} -monitor unix:$sock,server,nowait -netdev tap,id=net0,ifname=tap0,script=no,downscript=no -device virtio-net-pci,netdev=net0 -usbdevice tablet -drive file=$hda,if=virtio,boot=on
          '';
      preStop =
        ''
          echo 'system_powerdown' | ${pkgs.socat}/bin/socat - UNIX-CONNECT:/run/qemu-${name}.mon.sock
          sleep 10
        '';
    }) guests;
};}
