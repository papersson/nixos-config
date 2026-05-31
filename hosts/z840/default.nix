{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/zfs-tank.nix
  ];

  # Standard systemd-boot — no Secure Boot / Lanzaboote on this workstation.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Redistributable firmware blobs.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  networking.hostName = "z840";
  networking.hostId = "8f3a1c2b";

  # Static IP on the wired interface — outside the router's DHCP pool
  # (192.168.1.64–243), low end conventionally reserved for infra.
  networking.useDHCP = false;
  networking.interfaces.eno1 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.1.10";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "192.168.1.1" "1.1.1.1" "9.9.9.9" ];

  time.timeZone = "Europe/Stockholm";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Enable flakes + the new nix CLI globally.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  users.users.patrikpersson = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINcnhjkkwd2tLPzzMsLxAa9pGXHuRknfHPrkHU3eYgKr patrikcpersson@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJgkT0TXo+h8xeOpS7VWzJ4I7Regs8fMNGLJ1itMOpU1 patrikcpersson@gmail.com"
    ];
  };

  programs.zsh.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/patrikpersson/nixos-config";
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
  };

  environment.systemPackages = with pkgs; [
    git
    gh
    vim
    tree
    file
    curl
    wget
    htop
    pciutils
    usbutils
    smartmontools
    pkgs.claude-code
  ];

  systemd.tmpfiles.rules = [
    "d /etc/nixos 0755 patrikpersson users -"
  ];

  # OpenSSH — key-only auth, no root login, no passwords.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Jellyfin media server — Phase 1 of docs/media-server.md.
  #
  # Naming caveat: the dataset is `tank/jellyfin/config` (per the spec) but
  # what actually lives there is Jellyfin's *data* — the SQLite library DB,
  # plugin install dirs, user images, metadata cache. So `dataDir` (not
  # `configDir`) is what we point at the snapshot-protected dataset.
  # `configDir` (XML config) defaults to `${dataDir}/config` which is fine.
  # `cacheDir` is regenerable thumbnails — its own dataset, no snapshots.
  #
  # No hardwareAcceleration: the M5000 GPU can't decode HEVC, and remote
  # playback uses the 1080p arm of the dual-quality library instead of
  # transcoding. openFirewall opens 8096/8920 TCP + 1900/7359 UDP (LAN
  # discovery) — phase 4 will switch to a Caddy reverse proxy on 80/443.
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    dataDir = "/tank/jellyfin/config";
    cacheDir = "/tank/jellyfin/cache";
  };

  system.stateVersion = "25.11";
}
