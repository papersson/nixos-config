# Media server spec — z840

Spec doc for the first major homelab milestone: a self-hosted media server with full automation, replacing the Netflix-style consumption pattern. Scope is movies and TV (music / photos deferred to separate stacks later).

Status (2026-06-21):

- **Phase 0 (storage foundation)** — complete. 4× HC550 burned in clean (zero reallocated/pending/uncorrectable sectors across all four). `tank` pool created as raidz2 (chosen over raidz1 — see Decisions table), 28.1 TiB usable, `ashift=12`, dataset-level `compression=lz4 atime=off xattr=sa acltype=posixacl normalization=formD dnodesize=auto`. Declarative side at `modules/nixos/zfs-tank.nix`: import-only, `fileSystems` entries (mountpoint=legacy), sanoid snapshot policy, monthly `services.zfs.autoScrub`, and a `tank-drive-erc.service` that sets SCT ERC=7.0s on every boot (volatile setting). Imperative side at `docs/runbooks/zfs-pool-creation.md` (executed once; never re-run). **Dataset layout revised in Phase 2** (see below): `tank/media` is now a single dataset and `tank/media/{movies,tv}` + `tank/downloads` were retired in favour of nixarr's hardlink-friendly single-root model; `tank/nixarr` added for *arr state. See `docs/storage.md`.
- **Phase 1 (Jellyfin LAN-only)** — software complete. `services.jellyfin` in `hosts/z840/default.nix` with `dataDir=/tank/jellyfin/config`, `cacheDir=/tank/jellyfin/cache`, `openFirewall=true`. Test movie indexed with TMDB metadata. **Library paths must be repointed** to `/tank/media/library/{movies,shows}` (the old `/tank/media/{movies,tv}` datasets are gone). **Step 4 still pending**: 4K direct-play test on actual TV client — needs real 4K HEVC content (Phase 2 will supply) and a TV client (Apple TV / Shield / smart TV).
- **Phase 2 (*arr stack via nixarr)** — in progress; VPN plumbing verified. `nixarr` flake input + module wired into `hosts/z840`. Mullvad WireGuard config encrypted at `secrets/z840-wireguard.conf` (binary sops secret, decrypted at activation by the host key). qBittorrent confined to the `wg` namespace; **confinement verified** — host exits on the ISP (Sweden) while the qBittorrent namespace exits Mullvad (Germany/Frankfurt, `mullvad_exit_ip:true`). Sonarr / Radarr / Prowlarr / Bazarr running on the host. **Remaining**: repoint Jellyfin libraries; Prowlarr indexers (2–3 public) synced to Sonarr/Radarr; *arr download-client + root folders (`/tank/media/library/{movies,shows}`) + dual-quality profiles; validate end-to-end with public trackers. Usenet (Phase 2.5) deferred until that passes.
- **Phases 3, 4** — not started.

## Context

Why this is the first service:
- "Real consequences" principle — media is consumed daily, forcing the lab to work or be abandoned.
- "Build from components" — every piece (Jellyfin, nixarr, ZFS, Caddy, Tailscale, Mullvad) is independently understandable. No appliance.
- "Declarative everything" — nixarr provides a NixOS-native module that composes the *arr services; no Docker except as fallback.
- Storage is the long pole: the 4× HC550 raidz2 pool ("tank") needs to exist before any of the services land. Burn-in time gates everything else.

## Decisions

| Question | Decision | Reasoning |
|---|---|---|
| Media server software | **Jellyfin** | FOSS, no account dependency, native NixOS module. Plex's Apr 2025 $250 hike + paywalled HW transcoding violates FOSS-first. Emby has no compelling edge. |
| Content scope | Movies + TV (greenfield) | Music + photos are separate stacks (Navidrome/Immich) for later milestones. |
| Acquisition | Full *arr automation via nixarr | Sonarr + Radarr + Prowlarr + qBittorrent + Bazarr + Recyclarr. Single declarative module, WireGuard namespace for the downloader. |
| Indexer mix | Public + Usenet + private (over time) | Start public+VPN. Layer Usenet next ($10–15/mo provider + indexer). Pursue private tracker invites (PTP, BTN, HDBits) when ready. |
| VPN provider | **Mullvad** | nixarr's reference setup uses it. Cash/crypto accepted, no account email. Strong NixOS docs. WireGuard config only — no Mullvad app needed. |
| Remote access (phase 1) | **Tailscale** | Mesh WireGuard, zero NAT config. Free tier comfortable for solo use. Apple TV / phone clients trivial to add. |
| Remote access (phase 2) | Caddy + Let's Encrypt + domain | When friends/family come online. Public reverse proxy, TLS, Jellyfin's "Known Proxies" set so it reads `X-Forwarded-*` correctly. Adds Jellyseerr at this phase. |
| Quality target | **4K HDR at home, 1080p remote** | Dual-quality library via Sonarr/Radarr quality profiles. No transcoding ever fires. M5000 stays in the box for future VM passthrough. |
| Transcoding GPU | None (M5000 unused) | Maxwell-2 NVENC can't do HEVC with B-frames; GM204 doesn't decode HEVC at all. Even with a modern GPU, 4K over cellular is bandwidth-bound, not encode-bound. Dual-quality library sidesteps the whole problem. |
| Subtitle language | English only | Bazarr enabled, single language, OpenSubtitles + Subscene providers. |
| Quality profiles | **Recyclarr + TRaSH guides** | Community consensus for release scoring. Avoids hand-tuning Sonarr/Radarr custom formats. |
| Tdarr / batch re-encoding | **Skip** | 48 TB pool has runway. Revisit only if storage pressure becomes real. |
| Jellyseerr / request UI | **Skip phase 1** | Solo user has no need; Sonarr/Radarr UI is fine. Bolt on at phase 2 when others join. |
| Library structure | Canonical TMDB/TVDB layout | `Movies/Title (Year)/Title (Year).ext`, `TV/Show (Year)/Season XX/Show - SxxEyy - Episode.ext`. Year in folder is mandatory. *arr enforces this on import. |

## Hardware preconditions

Before any service deploys, the storage tier must exist:

- **HDD burn-in** on the 4× HC550 16 TB drives. Run `smartctl -t long /dev/sd{a,b,c,d}` in parallel (~18–30h each). Confirm zero reallocated sectors / pending sectors after. If any drive flags, RMA before pool creation.
- **ZFS pool `tank`** — raidz2 across the four drives (chosen over raidz1 because a resilver window on 16 TB drives is ~18–30h, during which raidz1 has zero parity; raidz2 keeps one parity drive during resilver at a 33% capacity cost). `ashift=12`, `recordsize=1M` set on the `tank/media` dataset for bulk sequential reads (default 128K kept on `tank/jellyfin` for the SQLite config).
- **Datasets** (revised in Phase 2 for nixarr's hardlink model — see `docs/storage.md`):
  - `tank/media` — **single** dataset (`recordsize=1M`). Holds both the qBittorrent download dir (`/tank/media/qbittorrent`) and the organized library (`/tank/media/library/{movies,shows}`). They share one filesystem so *arr import is an instant hardlink + atomic move, not a copy — the file seeds from the library with zero extra space. Hardlinks cannot cross ZFS datasets, which is why downloads and library are *not* split into separate datasets.
  - `tank/nixarr` — *arr SQLite state (`stateDir`; pool-default 128K, snapshot target)
  - `tank/jellyfin/config` — Jellyfin SQLite + plugins (frequent small writes; snapshot target)
  - `tank/jellyfin/cache` — metadata thumbnails (regenerable; snapshots skipped)
- **Snapshot policy**: hourly on `tank/jellyfin/config` + `tank/nixarr` (kept 24h), daily kept 7d, weekly kept 4w. `tank/media` snapshots weekly only (raidz2 already covers drive loss; the weekly sweep also catches in-progress torrents, cheap and self-pruning). No offsite backup until phase 2.

GPU stays in the box but is not loaded — `hardware.nvidia` is not enabled. M5000 reserved for a future Windows VM via libvirt + PCIe passthrough.

## Implementation phases

### Phase 0 — Storage foundation (blocking everything else)

1. Run `smartctl -t long` on all four HC550s. Wait for completion.
2. Verify SMART attributes clean. RMA any flagging drive.
3. Create the pool and datasets as a **one-shot imperative step, documented as a runbook, not a NixOS module** (see `docs/runbooks/zfs-pool-creation.md`): `zpool create -o ashift=12 tank raidz2 /dev/disk/by-id/...`, then `zfs create tank/media` and the rest (datasets above). Pool creation is deliberately never declarative. Declaring it is Option B's footgun, where a `--mode destroy,format` run wipes 28 TB. The pool is created exactly once and import-only forever after.
4. Declare only the **import-only, idempotent** half in a new `modules/nixos/zfs-tank.nix` imported from `hosts/z840/default.nix`: ZFS support, `boot.zfs.extraPools = [ "tank" ]`, `fileSystems` mount points for the datasets, and snapshot policy (`services.sanoid` or similar). Safe to re-run on every reinstall. It never creates the pool.
5. Verify pool: `zpool status`, `zfs list`, write a test file, confirm `recordsize=1M` on `tank/media`.

### Phase 1 — Jellyfin alone, LAN only

1. Add `services.jellyfin` to `hosts/z840/default.nix`. `configDir = /tank/jellyfin/config`, `cacheDir = /tank/jellyfin/cache`. `openFirewall = true` (LAN-trusted).
2. Hardware acceleration: **disabled** (no `hardwareAcceleration.enable`).
3. Mount a couple of test files manually under `tank/media/movies` with canonical naming. Confirm Jellyfin picks them up.
4. Add Apple TV / Shield / TV client. Confirm direct-play of a 4K file on LAN (no transcoding event in Jellyfin's playback dashboard).

### Phase 2 — *arr stack via nixarr

1. ✅ Add nixarr as a flake input (`github:nix-media-server/nixarr`, `inputs.nixpkgs.follows`). Bundles Maroka-chan/VPN-Confinement. Module imported via `nixarr.nixosModules.default` in `flake.nix`.
2. ✅ `nixarr.enable = true`, `mediaDir = /tank/media`, `stateDir = /tank/nixarr`, `mediaUsers = [ "jellyfin" ]`. `nixarr.vpn.enable = true` + `wgConf = config.sops.secrets."wireguard-mullvad".path`, `accessibleFrom = [ "192.168.1.0/24" ]`. Mullvad config is a binary sops secret at `secrets/z840-wireguard.conf` (decrypted at activation by the SSH host key — no operator key needed).
3. ✅ Sonarr, Radarr, Prowlarr, Bazarr enabled on the host; qBittorrent with `vpn.enable = true` (only the downloader is confined — the spec's choice). Confinement verified: host exits Sweden/ISP, qBittorrent namespace exits Germany/Mullvad. Recyclarr deferred.
4. ⬜ Sonarr/Radarr root folders → `/tank/media/library/{shows,movies}`. Download client → qBittorrent via nixarr's localhost proxy. (qBittorrent default download dir is `/tank/media/qbittorrent`, same dataset as the library, so imports hardlink.)
5. ⬜ Quality profiles: 4K Remux + 1080p Web-DL per title (dual-quality). Recyclarr/TRaSH sync optional, can layer later.
6. ⬜ Bazarr: English subtitles, OpenSubtitles provider.
7. ⬜ Prowlarr: add 2–3 public indexers, sync to Sonarr/Radarr, confirm searches return results.

> **Gotcha (first switch only):** `tank/nixarr` was created in the same `nixos-rebuild` as the services that use it, so `systemd-tmpfiles` created the service dirs *before* the dataset mounted — the mount then shadowed them and qBittorrent/Prowlarr failed (`ensureDirectoryExists` abort / `226/NAMESPACE`). Fix was `sudo systemd-tmpfiles --create` (with the dataset mounted) then re-`switch`. Does not recur: on a normal boot, `local-fs.target` mounts `tank/nixarr` before tmpfiles runs.

### Phase 3 — Remote access via Tailscale

1. `services.tailscale.enable = true` on z840. Auth via tailscale CLI (one-time `tailscale up`).
2. Install Tailscale on Mac/phone/laptop, log into the same tailnet.
3. Add Jellyfin URL using the z840's tailnet name (e.g. `http://z840:8096`) in client apps.
4. Confirm 1080p remote playback on phone over cellular works (direct-play, no transcoding).
5. ACLs in tailscale.json — solo phase is permissive default.

### Phase 4 — Friends/family + public proxy (when ready)

1. Register a domain (if not already). Configure dynamic DNS if no static WAN IP.
2. `services.caddy` reverse-proxying Jellyfin on a subdomain (e.g. `media.<domain>`).
3. Jellyfin "Known Proxies" set to Caddy's loopback so `X-Forwarded-*` headers are trusted.
4. Add Jellyseerr (oci-container — no NixOS module yet, or check at time of build) for friend/family request UI.
5. Tailscale ACLs tightened — friends use the public proxy, not the tailnet.
6. Account creation pattern for friends documented.

## Open questions to revisit

- **Domain registrar** — to settle at phase 4. Cloudflare for DNS regardless of registrar (free, supports DNS-01 for wildcard certs).
- **Apple TV 4K / Shield / smart TV** — which client devices the user actually has, to confirm direct-play paths. (Apple TV 4K is the gold standard; Shield is close; built-in smart TV apps vary wildly.)
- **Burn-in scheduling** — `smartctl -t long` takes 18–30h per drive but can run in parallel. Need uninterrupted power; coordinate with the planned UPS install.
- **Off-site backup** — phase 1 has none. ZFS replication to a small external drive (or cloud rclone target) for `tank/jellyfin/config` is worth a follow-up doc once the lab has a backup story.

## File map (when implemented)

- `hosts/z840/default.nix` — adds nixarr, services.jellyfin, services.tailscale wiring
- `modules/nixos/zfs-tank.nix` (new) — declares ZFS support, pool *import* (`boot.zfs.extraPools`), dataset mount points, and snapshot policy. Does **not** create the pool; that is a one-shot runbook step (see Phase 0).
- `modules/nixos/media-server.nix` (new) — nixarr composition (or fold into z840 default.nix if it stays simple)
- `secrets/z840.yaml` (new) — Mullvad WireGuard private key + any *arr API keys
- `.sops.yaml` — add z840 host recipient
- `~/nixos-config/CLAUDE.md` — drop reference to `secrets/z840.yaml` once it exists

## Non-goals

- Hardware transcoding (M5000 stays cold, no plan to buy a modern GPU for transcoding — dual-quality library handles all remote viewing without it)
- Music server (Navidrome / Funkwhale — separate milestone)
- Photo server (Immich — separate milestone)
- 4K over cellular (bandwidth-bound, not solvable at the encode layer)
- Public-internet exposure in phase 1 (Tailscale-only)
