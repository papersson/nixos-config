{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader. canTouchEfiVariables lets the installer write to NVRAM
  # so the firmware can find the bootloader on next boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "t14";
  networking.networkmanager.enable = true;

  users.users.patrikpersson = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # Set with `passwd patrikpersson` immediately after first boot.
    initialPassword = "changeme";
  };

  services.openssh.enable = true;

  # Pin the semantics of stateful options (databases, etc.) to the
  # NixOS release this system was *first* installed under. Do not
  # change this after install — see `man configuration.nix`.
  system.stateVersion = "25.11";
}
