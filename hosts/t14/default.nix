{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader. canTouchEfiVariables lets the installer write to NVRAM so
  # the firmware can find the bootloader on next boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Latest mainline kernel — better hardware support on recent ThinkPads.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "t14";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Stockholm";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.patrikpersson = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # Set with `passwd patrikpersson` immediately after first boot.
    initialPassword = "changeme";
  };

  services.openssh.enable = true;

  # Pin stateful-option semantics to the release this host was first
  # installed under. Do not change after install — see `man configuration.nix`.
  system.stateVersion = "25.11";
}
