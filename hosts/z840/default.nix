{ config, lib, pkgs, ... }:

let
  # `arr-apikey <app>` — print one *arr app's API key. The config.xml files
  # live in 0700 per-service dirs, so this runs via a sudo rule pinned to this
  # exact store path + argument (see security.sudo.extraRules). It's the
  # narrowest grant that lets Claude drive Radarr/Sonarr/Prowlarr over their
  # HTTP APIs (add movies/shows, inspect + fix the download queue) — it prints
  # the key and nothing else from the file.
  arrApiKey = pkgs.writeShellApplication {
    name = "arr-apikey";
    runtimeInputs = [ pkgs.gnused ];
    text = ''
      case "''${1:-}" in
        radarr|sonarr|prowlarr) ;;
        *) echo "usage: arr-apikey radarr|sonarr|prowlarr" >&2; exit 2 ;;
      esac
      sed -n 's:.*<ApiKey>\([^<]*\)</ApiKey>.*:\1:p' "/tank/nixarr/$1/config.xml"
    '';
  };
  arrApps = [ "radarr" "sonarr" "prowlarr" ];

  # `media-queue` — what's downloading and is it moving? Radarr + Sonarr
  # queues (incl. their warnings/errors) and every qBittorrent torrent with
  # state, progress, speed, seeds and time since last activity. qBittorrent's
  # API is reached on the VPN bridge (192.168.15.1:8085), which nixarr
  # whitelists for unauthenticated access from the host. `--json` emits the
  # raw combined data for scripting; exit 1 if anything looks stuck.
  mediaQueue = pkgs.writeShellApplication {
    name = "media-queue";
    runtimeInputs = with pkgs; [ curl jq coreutils ];
    text = ''
      qbit=http://192.168.15.1:8085/api/v2
      key() { sudo -n ${arrApiKey}/bin/arr-apikey "$1"; }
      arr() { # app port
        curl -sf --max-time 15 -H "X-Api-Key: $(key "$1")" \
          "http://localhost:$2/api/v3/queue?pageSize=200&includeUnknownMovieItems=true&includeUnknownSeriesItems=true&includeMovie=true&includeSeries=true&includeEpisode=true" \
          || echo '{"records":[],"error":"unreachable"}'
      }
      radarr=$(arr radarr 7878)
      sonarr=$(arr sonarr 8989)
      torrents=$(curl -sf --max-time 15 "$qbit/torrents/info" || echo '[]')
      all=$(jq -n --argjson r "$radarr" --argjson s "$sonarr" --argjson t "$torrents" \
        '{radarr: $r.records, sonarr: $s.records, torrents: $t, now: now}')

      if [ "''${1:-}" = --json ]; then echo "$all"; exit 0; fi

      echo "$all" | jq -r '
        def gb: . / 1073741824 | (. * 100 | round / 100 | tostring) + " GB";
        def mins: (. / 60 | floor);
        def arrline: "  [\(.status)/\(.trackedDownloadState // "-")] \(.title)  left=\(.sizeleft | gb) eta=\(.timeleft // "?")"
          + (if ((.statusMessages // []) | length) > 0 then "\n      ! " + ([.statusMessages[].messages[]] | join("; ")) else "" end)
          + (if .errorMessage then "\n      ! " + .errorMessage else "" end);
        "Radarr queue (\(.radarr | length)):", (.radarr[] | arrline),
        "", "Sonarr queue (\(.sonarr | length)):", (.sonarr[] | arrline),
        "", "qBittorrent (\(.torrents | length)):",
        (.now as $now | .torrents[] |
          "  [\(.state)] \(.progress * 1000 | floor / 10)%  \(.dlspeed / 1024 | floor) KiB/s  seeds=\(.num_seeds)/\(.num_complete)  idle=\(($now - .last_activity) | mins)m  \(.category)  \(.name)")
      '

      # stuck = qBittorrent says stalled/errored/missing, or an *arr item
      # carries a warning/error state
      stuck=$(echo "$all" | jq '
        ([.torrents[] | select(.state | test("stalledDL|error|missingFiles|metaDL"))] | length)
        + ([(.radarr + .sonarr)[] | select(.trackedDownloadStatus != "ok" or .status == "warning" or .status == "failed")] | length)')
      if [ "$stuck" -gt 0 ]; then echo; echo "! $stuck item(s) look stuck"; exit 1; fi
    '';
  };

  # `media-watch [interval-seconds]` — block until something needs attention,
  # then print why + the queue and exit. Meant to run in the background so a
  # caller (Claude) is woken only on events, not on a timer:
  #   exit 0 "QUEUE EMPTY"     — nothing left in Radarr/Sonarr
  #   exit 0 "LEFT QUEUE: …"   — an item imported (or was removed)
  #   exit 1 "NO PROGRESS: …"  — an *active* torrent downloaded 0 bytes over
  #                              one interval (default 15 min). Queued torrents
  #                              are ignored — waiting their turn isn't stuck,
  #                              and Radarr's "stalled" warning right after a
  #                              grab is usually transient, so bytes are judged.
  mediaWatch = pkgs.writeShellApplication {
    name = "media-watch";
    runtimeInputs = [ mediaQueue pkgs.jq pkgs.coreutils ];
    text = ''
      interval=''${1:-900}
      prev=""; prevq=""
      while true; do
        j=$(media-queue --json)
        cur=$(echo "$j" | jq -c '[.torrents[] | select(.progress < 1 and (.state | test("^(downloading|stalledDL|metaDL|forcedDL)$"))) | {h: .hash, n: .name, d: .downloaded}]')
        q=$(echo "$j" | jq -c '[(.radarr + .sonarr)[].title] | sort')
        if [ "$(echo "$q" | jq length)" -eq 0 ]; then
          echo "QUEUE EMPTY $(date +%H:%M)"; media-queue || true; exit 0
        fi
        if [ -n "$prevq" ]; then
          gone=$(jq -nc --argjson a "$prevq" --argjson b "$q" '$a - $b')
          if [ "$gone" != "[]" ]; then
            echo "LEFT QUEUE $(date +%H:%M): $gone"; media-queue || true; exit 0
          fi
        fi
        if [ -n "$prev" ]; then
          stuck=$(jq -nc --argjson a "$prev" --argjson b "$cur" '[$b[] as $x | $a[] | select(.h == $x.h and .d == $x.d) | .n]')
          if [ "$stuck" != "[]" ]; then
            echo "NO PROGRESS $(date +%H:%M): $stuck"; media-queue || true; exit 1
          fi
        fi
        prev=$cur; prevq=$q
        sleep "$interval"
      done
    '';
  };
in
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
  #   - reading the Radarr/Sonarr/Prowlarr API keys (arr-apikey), so Claude
  #     can add media and manage the download queue over the HTTP APIs.
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
      # --- *arr API keys (one exact rule per app; see arrApiKey above) ---
      ++ map (app: "${arrApiKey}/bin/arr-apikey ${app}") arrApps
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

  # `media-health` — on-demand health check for the whole media stack. Run it
  # whenever you wonder "is everything OK?". Every check is a *fact*, not a
  # proxy: the VPN test in particular verifies a completed WireGuard handshake
  # and a real Mullvad exit, because a dead tunnel looks identical to a live
  # one from the outside (services "active", endpoint pingable) — that exact
  # blind spot hid a retired relay for ~8 weeks. Exit code 0 = all green.
  # Uses the scoped sudo rules above for the namespace + service checks.
  environment.systemPackages = let
    mediaHealth = pkgs.writeShellApplication {
      name = "media-health";
      runtimeInputs = with pkgs; [ curl jq iproute2 wireguard-tools coreutils gnugrep gawk ];
      text = ''
        sw=/run/current-system/sw/bin
        wgbin=${pkgs.wireguard-tools}/bin/wg
        fail=0
        ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
        bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }
        warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
        hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

        # ---------- services ----------
        hdr "Services"
        for u in wg qbittorrent sonarr radarr prowlarr bazarr seerr jellyfin flaresolverr tailscaled; do
          if [ "$(systemctl is-active "$u.service" 2>/dev/null)" = active ]; then ok "$u"; else bad "$u is $(systemctl is-active "$u.service" 2>/dev/null)"; fi
        done

        # ---------- VPN tunnel: the check that actually matters ----------
        hdr "VPN tunnel (Mullvad)"
        hs=$(sudo -n "$sw/ip" netns exec wg "$wgbin" show wg0 latest-handshakes 2>/dev/null | awk '{print $2}')
        now=$(date +%s)
        if [ -z "''${hs:-}" ] || [ "$hs" = 0 ]; then
          bad "no WireGuard handshake has EVER completed — the relay is not talking to us"
          warn "likely: relay retired / key rejected / account lapsed. Check: mullvad.net/en/account, and whether the config's Endpoint is still in api.mullvad.net/www/relays/wireguard/"
        else
          age=$(( now - hs ))
          if [ "$age" -le 180 ]; then ok "handshake $age s ago"; else bad "last handshake $age s ago (>3 min) — tunnel is stale"; fi
        fi
        rx=$(sudo -n "$sw/ip" netns exec wg "$wgbin" show wg0 transfer 2>/dev/null | awk '{print $2}')
        if [ -n "''${rx:-}" ] && [ "$rx" -gt 0 ]; then ok "$rx bytes received through tunnel"; else bad "0 bytes received — nothing is coming back through the tunnel"; fi
        exitjson=$(sudo -n "$sw/ip" netns exec wg curl -s --max-time 10 https://am.i.mullvad.net/json 2>/dev/null || true)
        if [ -n "$exitjson" ] && [ "$(echo "$exitjson" | jq -r .mullvad_exit_ip)" = true ]; then
          ok "exit: $(echo "$exitjson" | jq -r '"\(.ip)  \(.city), \(.country)"') (mullvad_exit_ip=true)"
        else
          bad "no internet inside the tunnel (curl to am.i.mullvad.net failed)"
        fi
        # leak guard: the HOST must NOT exit via mullvad
        hostjson=$(curl -s --max-time 10 https://am.i.mullvad.net/json 2>/dev/null || true)
        if [ -n "$hostjson" ]; then
          if [ "$(echo "$hostjson" | jq -r .mullvad_exit_ip)" = false ]; then ok "host exits on ISP ($(echo "$hostjson" | jq -r .country)) — not leaking the other way"; else warn "host appears to exit via Mullvad — check routing"; fi
        else warn "host has no internet?"; fi
        # DNS *inside* the namespace, via the resolver the apps actually use.
        # A tunnel can pass traffic perfectly while DNS is black-holed (e.g. a
        # 10.x resolver caught by the 10.0.0.0/8 -> LAN route) — then torrents
        # show "0 seeds" on healthy swarms. Test the configured resolver
        # explicitly and confirm it routes via wg0, not the LAN.
        ns=$(sudo -n "$sw/ip" netns exec wg cat /etc/resolv.conf 2>/dev/null | awk '/^nameserver/{print $2; exit}')
        if [ -n "''${ns:-}" ]; then
          via=$(sudo -n "$sw/ip" netns exec wg ip route get "$ns" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')
          if [ "$via" = wg0 ]; then ok "namespace DNS $ns routes via wg0"; else bad "namespace DNS $ns routes via ''${via:-?} (NOT the tunnel) — lookups black-holed; use a non-10.x resolver in the wg config"; fi
          if sudo -n "$sw/ip" netns exec wg getent hosts tracker.opentrackr.org >/dev/null 2>&1; then ok "namespace resolves tracker hostnames"; else bad "namespace cannot resolve tracker hostnames — torrents will show 0 seeds"; fi
        else
          bad "namespace has no nameserver configured"
        fi
        # is the pinned relay still a live mullvad relay?
        ep=$(sudo -n "$sw/ip" netns exec wg "$wgbin" show wg0 endpoints 2>/dev/null | awk '{print $2}' | cut -d: -f1)
        if [ -n "''${ep:-}" ]; then
          rel=$(curl -s --max-time 15 https://api.mullvad.net/www/relays/wireguard/ 2>/dev/null | jq -r --arg ip "$ep" '.[] | select(.ipv4_addr_in==$ip) | "\(.hostname) active=\(.active)"' 2>/dev/null || true)
          if [ -n "$rel" ]; then ok "relay $ep is in Mullvad's live list ($rel)"; else bad "relay $ep is NOT in Mullvad's relay list — it was retired; rotate the wg config"; fi
        fi

        # ---------- downloads / storage ----------
        hdr "Downloads & storage"
        stuck=$(find /tank/media/qbittorrent/.incomplete -type f -mmin +120 2>/dev/null | wc -l)
        if [ "$stuck" -eq 0 ]; then ok "no incomplete downloads untouched for >2h"; else warn "$stuck incomplete file(s) not written to in >2h (stalled torrents?)"; fi
        used=$(zfs list -H -o used tank 2>/dev/null); avail=$(zfs list -H -o avail tank 2>/dev/null)
        ok "tank: $used used, $avail free"
        pool=$(zpool status -x 2>/dev/null); if [ "$pool" = "all pools are healthy" ]; then ok "zpool: healthy"; else bad "zpool: $pool"; fi

        # ---------- app reachability (host) ----------
        hdr "App endpoints"
        for pair in "jellyfin:8096" "sonarr:8989" "radarr:7878" "prowlarr:9696" "bazarr:6767" "seerr:5055"; do
          n=''${pair%%:*}; p=''${pair##*:}
          code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:$p" || true)
          # any 2xx/3xx/401/403 = the app answered (3xx = redirect to login, healthy)
          case "$code" in 2??|3??|401|403) ok "$n :$p (HTTP $code)";; *) bad "$n :$p not responding (HTTP ''${code:-none})";; esac
        done
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://192.168.15.1:8085 || true)
        case "$code" in 200|401|403) ok "qbittorrent :8085 via VPN bridge (HTTP $code)";; *) bad "qbittorrent :8085 not responding (HTTP ''${code:-none})";; esac

        echo
        if [ "$fail" -eq 0 ]; then printf '\033[32m\033[1mALL GREEN\033[0m\n'; else printf '\033[31m\033[1mPROBLEMS FOUND — see ✗ above\033[0m\n'; fi
        exit "$fail"
      '';
    };
  in [ mediaHealth mediaQueue mediaWatch arrApiKey ] ++ (with pkgs; [
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
  ]);

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
        # Download one torrent at a time so each title finishes sooner instead
        # of N sharing the line. A torrent under 500 KiB/s for 60 s counts as
        # "slow" and stops holding the slot (IgnoreSlowTorrentsForQueueing is
        # on via nixarr), so a weak swarm can't block the queue.
        "Session\\MaxActiveDownloads" = 1;
        "Session\\SlowTorrentsDownloadRate" = 500;
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
