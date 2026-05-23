# Media server spec — z840

Spec doc for the first major homelab milestone: a self-hosted media server with full automation, replacing the Netflix-style consumption pattern. Scope is movies and TV (music / photos deferred to separate stacks later).

Status: planning. No code on disk yet. This document is the contract for what gets built.

## Context

Why this is the first service:
- "Real consequences" principle — media is consumed daily, forcing the lab to work or be abandoned.
- "Build from components" — every piece (Jellyfin, nixarr, ZFS, Caddy, Tailscale, Mullvad) is independently understandable. No appliance.
- "Declarative everything" — nixarr provides a NixOS-native module that composes the *arr services; no Docker except as fallback.
- Storage is the long pole: the 4× HC550 raidz1 pool ("tank") needs to exist before any of the services land. Burn-in time gates everything else.

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

- **HDD burn-in** on the 4× HC550 16 TB drives. Run `smartctl -t long /dev/sd{b,c,d,e}` in parallel (~18–30h each). Confirm zero reallocated sectors / pending sectors after. If any drive flags, RMA before pool creation.
- **ZFS pool `tank`** — raidz1 across the four drives. `ashift=12`, `recordsize=1M` set on the `tank/media` dataset for bulk sequential reads (default 128K kept on `tank/jellyfin` for the SQLite config).
- **Datasets**:
  - `tank/media/movies` — Radarr root
  - `tank/media/tv` — Sonarr root
  - `tank/jellyfin/config` — Jellyfin SQLite + plugins (frequent small writes; snapshot target)
  - `tank/jellyfin/cache` — metadata thumbnails (regenerable; snapshots skipped)
  - `tank/downloads` — qBittorrent incomplete + complete dirs (chmod-compatible with Sonarr/Radarr import)
- **Snapshot policy**: hourly on `tank/jellyfin/config` (kept 24h), daily kept 7d, weekly kept 4w. Media datasets snapshot weekly only (raidz1 already covers drive loss). No offsite backup until phase 2.

GPU stays in the box but is not loaded — `hardware.nvidia` is not enabled. M5000 reserved for a future Windows VM via libvirt + PCIe passthrough.

## Implementation phases

### Phase 0 — Storage foundation (blocking everything else)

1. Run `smartctl -t long` on all four HC550s. Wait for completion.
2. Verify SMART attributes clean. RMA any flagging drive.
3. Create the pool and datasets as a **one-shot imperative step, documented as a runbook, not a NixOS module**: `zpool create -o ashift=12 tank raidz1 /dev/disk/by-id/...`, then `zfs create tank/media` and the rest (datasets above). Pool creation is deliberately never declarative. Declaring it is Option B's footgun, where a `--mode destroy,format` run wipes 48 TB. The pool is created exactly once and import-only forever after.
4. Declare only the **import-only, idempotent** half in a new `modules/nixos/zfs-tank.nix` imported from `hosts/z840/default.nix`: ZFS support, `boot.zfs.extraPools = [ "tank" ]`, `fileSystems` mount points for the datasets, and snapshot policy (`services.sanoid` or similar). Safe to re-run on every reinstall. It never creates the pool.
5. Verify pool: `zpool status`, `zfs list`, write a test file, confirm `recordsize=1M` on `tank/media`.

### Phase 1 — Jellyfin alone, LAN only

1. Add `services.jellyfin` to `hosts/z840/default.nix`. `configDir = /tank/jellyfin/config`, `cacheDir = /tank/jellyfin/cache`. `openFirewall = true` (LAN-trusted).
2. Hardware acceleration: **disabled** (no `hardwareAcceleration.enable`).
3. Mount a couple of test files manually under `tank/media/movies` with canonical naming. Confirm Jellyfin picks them up.
4. Add Apple TV / Shield / TV client. Confirm direct-play of a 4K file on LAN (no transcoding event in Jellyfin's playback dashboard).

### Phase 2 — *arr stack via nixarr

1. Add nixarr as a flake input. Pin to a tag, not master.
2. Configure `nixarr.enable = true`, `nixarr.vpn.enable = true` with Mullvad WireGuard config (key in sops-encrypted `secrets/z840.yaml`).
3. Enable Sonarr, Radarr, Prowlarr, Bazarr, Recyclarr. qBittorrent inside the VPN namespace.
4. Sonarr/Radarr root folders → `tank/media/{tv,movies}`. Download client → qBittorrent, completed dir → `tank/downloads/complete`.
5. Recyclarr config syncs TRaSH-guide quality profiles for both 1080p and 2160p (4K). Sonarr/Radarr profiles configured to grab 4K Remux + 1080p Web-DL per title.
6. Bazarr: English subtitles, OpenSubtitles + Subscene providers.
7. Prowlarr: add a few public trackers initially. Confirm indexer searches return results through the VPN namespace.

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
