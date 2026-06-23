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
  # Cloudflare first, not the Telia router (192.168.1.1): Swedish ISPs
  # DNS-block torrent indexers at their resolver, and glibc stops at the first
  # nameserver that answers — so a blocking resolver in front shadows the rest.
  # Prowlarr (on the host) needs these to resolve. 9.9.9.9 is a non-Telia
  # fallback. The host has no usable IPv6, so no v6 resolver is listed.
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" "9.9.9.9" ];
  # Write /etc/resolv.conf statically from the list above. Without this,
  # resolvconf lets a transient boot-time subscriber prepend the Telia
  # resolver, which shadows Cloudflare (glibc stops at the first responder)
  # and re-blocks the indexers. A static-IP server needs no dynamic resolvconf.
  networking.resolvconf.enable = false;

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

  # Tailscale — private mesh network across my own devices (Phase 3 of
  # docs/media-server.md). Lets the phone/laptop reach z840 from anywhere
  # (Jellyfin over cellular) without exposing ports to the public internet.
  # Auth is a one-time interactive `sudo tailscale up` (no auth-key secret).
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641 for direct (non-relayed) connections
  };

  # Trust the tailnet interface: every device on my tailnet can reach all of
  # z840's ports, including the *arr web UIs (8989/7878/9696/6767) and
  # qBittorrent — so management no longer needs an SSH port-forward, while the
  # LAN firewall stays closed to everything but SSH + Jellyfin. Safe because
  # the tailnet is solo (only my own authenticated devices). Revisit if other
  # people are ever added to the tailnet (Phase 4).
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

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

  # sops: z840 derives its age identity from the SSH host key, so the Mullvad
  # WireGuard config decrypts at activation with no operator key present. The
  # secret is a whole-file (binary) config, encrypted to host + user in
  # secrets/z840-wireguard.conf (see .sops.yaml). nixarr reads the decrypted
  # path to bring up the VPN namespace.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets."wireguard-mullvad" = {
    sopsFile = ../../secrets/z840-wireguard.conf;
    format = "binary";
  };

  # nixarr — *arr automation suite, Phase 2 of docs/media-server.md.
  #
  # Storage model (see modules/nixos/zfs-tank.nix): mediaDir is the single
  # `tank/media` dataset so downloads (`/tank/media/qbittorrent`) and the
  # organized library (`/tank/media/library/...`) share one filesystem and
  # *arr imports are instant hardlinks, not copies. stateDir lives on its own
  # snapshot-protected `tank/nixarr` dataset.
  #
  # VPN: only qBittorrent is confined to the Mullvad WireGuard namespace (the
  # spec's choice — the downloader is the only thing that must never touch the
  # bare WAN IP). The *arr apps run on the host and reach qBittorrent's API
  # through nixarr's localhost proxy. accessibleFrom lets the LAN reach the
  # confined qBittorrent web UI.
  nixarr = {
    enable = true;
    mediaDir = "/tank/media";
    stateDir = "/tank/nixarr";

    # Let Jellyfin (separate service) read the media group's library.
    mediaUsers = [ "jellyfin" ];

    vpn = {
      enable = true;
      wgConf = config.sops.secrets."wireguard-mullvad".path;
      accessibleFrom = [ "192.168.1.0/24" ];
    };

    sonarr.enable = true;
    radarr.enable = true;
    # Prowlarr runs on the host, NOT in the VPN namespace. Routing it through
    # Mullvad doesn't work: Mullvad force-redirects all port-53 DNS to its own
    # resolver, which filters the major torrent indexers, and only DoH (443)
    # escapes that. Rather than run a DoH proxy inside the namespace, we resolve
    # on the host via Cloudflare (see networking.nameservers) and accept that
    # indexer lookups ride the ISP line. Downloads still tunnel through Mullvad
    # (qBittorrent below) — that's the part that must never touch the bare IP.
    prowlarr.enable = true;
    bazarr.enable = true;
    qbittorrent = {
      enable = true;
      vpn.enable = true;
    };
  };

  # Make qBittorrent's downloads group-writable so the *arr services (all in
  # the `media` group) can HARDLINK them into the library instead of copying.
  # The kernel's fs.protected_hardlinks=1 only lets you hardlink a file you own
  # or can write; nixarr's default umask (0022) yields 0644 downloads (group
  # read-only), so Radarr/Sonarr fall back to a full copy — defeating the
  # single-dataset layout. 0002 → 0664, group `media` can hardlink. Applies to
  # future downloads only. (Standard *arr/TRaSH-guide hardlink fix.)
  systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";

  # FlareSolverr — headless-browser proxy that solves the Cloudflare "are you
  # a bot" challenge for Prowlarr. Most public indexers (1337x, TorrentGalaxy,
  # …) sit behind it, and a plain HTTP client can't pass the JS challenge.
  # Listens on localhost:8191; Prowlarr uses it as a tagged indexer proxy.
  # Runs on the host alongside Prowlarr (indexer access is already on the ISP
  # line per the nixarr notes above); not firewall-exposed.
  services.flaresolverr.enable = true;

  system.stateVersion = "25.11";
}
