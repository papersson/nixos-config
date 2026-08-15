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

  # Scoped passwordless sudo for the operator account (which Claude Code runs
  # as). The point of this box is that Claude runs it, so grant the operations
  # that make it useful without a human paste-back — while keeping the two
  # things that could ruin the day behind a password: destroying data and
  # losing the ability to log in.
  #
  # Granted (NOPASSWD):
  #   - read-only diagnostics: journalctl, systemctl status/show/is-active,
  #     zpool status, zfs list/get, and looking inside the VPN namespace
  #     (ip netns exec wg …) for curl/ip/getent/wg.
  #   - service control on the MEDIA STACK only (restart/start/stop/reload):
  #     wg, qbittorrent, qui, sonarr, radarr, prowlarr, bazarr, seerr,
  #     jellyfin, flaresolverr, tailscaled, nginx.
  #   - the rebuild itself: nh os switch / nixos-rebuild. Reversible via
  #     generation rollback, which is what makes it reasonable to grant.
  #
  # Deliberately NOT granted: rm/dd/mkfs as root, zfs destroy / zpool
  # create|destroy|labelclear, reboot/poweroff, anything touching sops keys.
  # Those stay a "please run this" from Claude. Paths use the stable
  # /run/current-system/sw/bin so rules survive rebuilds.
  security.sudo.extraRules = let
    sw = "/run/current-system/sw/bin";
    mediaUnits = [
      "wg" "qbittorrent" "qui" "sonarr" "radarr" "prowlarr" "bazarr" "seerr"
      "jellyfin" "flaresolverr" "tailscaled" "nginx"
    ];
    nopasswd = command: { inherit command; options = [ "NOPASSWD" ]; };
    # one rule per (verb, unit) pair — sudoers has no brace-expansion
    serviceRules = lib.concatMap (verb:
      map (u: "${sw}/systemctl ${verb} ${u}.service") mediaUnits
      ++ map (u: "${sw}/systemctl ${verb} ${u}") mediaUnits
    ) [ "restart" "start" "stop" "reload" ];
  in [{
    users = [ "patrikpersson" ];
    commands = map nopasswd (
      # --- read-only diagnostics ---
      [
        "${sw}/journalctl *"
        "${sw}/systemctl status *"
        "${sw}/systemctl show *"
        "${sw}/systemctl is-active *"
        "${sw}/systemctl list-units *"
        "${sw}/zpool status *"
        "${sw}/zpool status"
        "${sw}/zfs list *"
        "${sw}/zfs list"
        "${sw}/zfs get *"
        # look inside the VPN namespace (read-only tools only)
        "${sw}/ip netns exec wg curl *"
        "${sw}/ip netns exec wg ip *"
        "${sw}/ip netns exec wg getent *"
        # `wg` isn't on PATH inside the namespace, so grant it by store path
        # (read-only `show` subcommand only).
        "${sw}/ip netns exec wg ${pkgs.wireguard-tools}/bin/wg show*"
        "${sw}/ip netns exec wg ${pkgs.wireguard-tools}/bin/wg"
        "${sw}/ip netns exec wg cat /etc/resolv.conf"
      ]
      # --- media-stack service control ---
      ++ serviceRules
      # --- the rebuild ---
      ++ [
        "${sw}/nh os switch*"
        "${sw}/nh os boot*"
        "${sw}/nh os test*"
        "${sw}/nixos-rebuild switch*"
        "${sw}/nixos-rebuild test*"
        "${sw}/nixos-rebuild boot*"
      ]
    );
  }];

  programs.nh = {
    enable = true;
    flake = "/home/patrikpersson/nixos-config";
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
  };

  # nix-ld: install a working dynamic loader at /lib64/ld-linux-x86-64.so.2 so
  # prebuilt (non-Nix) ELF binaries can run on this otherwise-FHS-less system.
  # Needed by the Claude *desktop* app's remote-over-SSH feature, which downloads
  # its own dynamically-linked `claude` CLI into ~/.claude/remote/ccd-cli and
  # execs it — without nix-ld the kernel hits NixOS's stub loader and the app
  # reports "installed cli ... is not runnable". The libraries below cover what a
  # Bun/Node-compiled binary links against. Reversible: drop this block, rebuild.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++ / libgcc_s
      zlib
      openssl
    ];
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
  #
  # `--ssh` makes tailscaled act as an SSH server on the tailnet interface, so
  # the phone (Claude app) can `ssh patrikpersson@z840.tail7bf5b7.ts.net` with
  # auth handled by the tailnet itself — no SSH key to copy off the phone, and
  # nothing exposed to the LAN/public side (OpenSSH there stays key-only). Note:
  # extraUpFlags is only auto-applied by tailscaled-autoconnect when an
  # authKeyFile is set; with interactive auth this flag documents intent but the
  # actual toggle is a one-time `sudo tailscale set --ssh` (surgical: leaves
  # other prefs untouched, reverse with `--ssh=false`).
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641 for direct (non-relayed) connections
    extraUpFlags = [ "--ssh" ];
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
      # Don't seed forever. nixarr defaults to unlimited (GlobalMaxRatio = -1,
      # "let *arr apps manage"); instead seed to ratio 2.0 OR 14 days, whichever
      # comes first, then remove the torrent from qBittorrent. Files are kept —
      # and since *arr imports hardlink into the library, the removed torrent's
      # data still lives there under the same inode, so this only clears the
      # torrent list, never anything you can watch. (Keys use qBittorrent.conf's
      # `Session\...` INI names; MaxRatioAction 1 = remove torrent, keep data.)
      extraConfig.BitTorrent = {
        "Session\\GlobalMaxRatio" = 2.0;
        "Session\\GlobalMaxSeedingMinutes" = 20160;
        "Session\\MaxRatioAction" = 1;
      };
    };

    # Jellyseerr (nixarr calls it `seerr`) — discovery + request front end on
    # the host (web UI on :5055, state under tank/nixarr/seerr). Browse
    # trending/popular, click to request → it hands off to Radarr/Sonarr. Runs
    # on the host so it reaches Jellyfin + the *arr APIs over localhost; not
    # firewall-opened — reached over Tailscale (trusted iface) like the others.
    seerr.enable = true;
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
