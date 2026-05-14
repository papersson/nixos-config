{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/thinkpad-t14-gen4.nix
    ../../modules/nixos/desktop-hyprland.nix
    ../../modules/nixos/wifi.nix
  ];

  # Bootloader: Lanzaboote replaces systemd-boot. It signs a Unified Kernel
  # Image (kernel + initrd + cmdline) with keys held at /var/lib/sbctl so
  # firmware-level Secure Boot can verify everything we boot. systemd-boot
  # itself is mkForce'd off because both bootloaders can't coexist; mkForce
  # is belt-and-braces in case a nixos-hardware module re-enables it later.
  # canTouchEfiVariables stays — Lanzaboote uses it the same way.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

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

  # Allow installing packages with non-free licenses (currently: claude-code).
  # Tighten later with `nixpkgs.config.allowUnfreePredicate` if you want an
  # explicit allowlist of which unfree packages are permitted.
  nixpkgs.config.allowUnfree = true;

  users.users.patrikpersson = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    shell = pkgs.zsh;
  };

  # System-level zsh enable is required so login shells set up properly
  # (PAM session, /etc/zshenv, completion paths). User-level zsh config
  # lives in home-manager.
  programs.zsh.enable = true;

  # `nh` wraps nixos-rebuild with closure diffs and nix-output-monitor.
  # `nh os switch` from anywhere rebuilds /etc/nixos#t14 without flag
  # juggling. `nh clean` retires generations older than 7 days while
  # keeping at least the 5 most recent, and (unlike `nix-collect-garbage`)
  # also cleans up direnv-managed GC roots.
  #
  # nh asserts against `nix.gc.automatic = true` — pick one. We pick nh.
  programs.nh = {
    enable = true;
    flake = "/etc/nixos";
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
  };

  # Base CLI tooling needed on first login. Anything user-scoped will move
  # into home-manager later; this list stays small and system-wide.
  environment.systemPackages = with pkgs; [
    # Source control + GitHub plumbing
    git
    gh

    # Editors / file inspection
    vim
    tree
    file

    # Networking / monitoring
    curl
    wget
    htop

    # Hardware introspection
    pciutils
    usbutils

    # Agentic CLI assistant — pulled from unstable for faster updates.
    # Unfree (Anthropic Commercial Terms); gated by allowUnfree above.
    pkgs.unstable.claude-code

    # Secure Boot tooling. Used out-of-band (sbctl create-keys,
    # sbctl enroll-keys, sbctl status/verify); the lanzaboote module
    # itself isn't imported until keys are enrolled in firmware.
    sbctl
  ];

  # Keep /etc/nixos writable by the primary user so editing the flake
  # doesn't require sudo. Rebuilds still need sudo (nixos-rebuild switch).
  systemd.tmpfiles.rules = [
    "d /etc/nixos 0755 patrikpersson users -"
  ];

  services.openssh.enable = true;

  # Pin stateful-option semantics to the release this host was first
  # installed under. Do not change after install — see `man configuration.nix`.
  system.stateVersion = "25.11";
}
