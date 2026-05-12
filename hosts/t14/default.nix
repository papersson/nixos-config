{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/thinkpad-t14-gen4.nix
    ../../modules/nixos/desktop-gnome.nix
  ];

  # Bootloader. canTouchEfiVariables lets the installer write to NVRAM so
  # the firmware can find the bootloader on next boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Latest mainline kernel — better hardware support on recent ThinkPads
  # (AX211 Wi-Fi firmware, Thunderbolt hotplug, libfprint protocol fixes).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Redistributable firmware blobs (Intel AX211 Wi-Fi/BT, SOF audio DSP).
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  networking.hostName = "t14";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Stockholm";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Enable flakes + the new nix CLI globally so plain `nix build`,
  # `nix shell`, `nix flake` work without per-invocation flags.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.patrikpersson = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

  # Base CLI tooling needed on first login. Anything user-scoped will move
  # into home-manager later; this list stays small and system-wide.
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    htop
    tree
    file
    pciutils
    usbutils
  ];

  services.openssh.enable = true;

  # Pin stateful-option semantics to the release this host was first
  # installed under. Do not change after install — see `man configuration.nix`.
  system.stateVersion = "25.11";
}
