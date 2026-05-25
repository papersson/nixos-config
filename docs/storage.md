# z840 storage conventions

`tank` (4× HC550 raidz2, ~28 TiB usable) is the bulk-storage pool for *any*
workload that needs durable space on the z840. Media is the first tenant
(see `media-server.md`); it is not the only one.

A future `fast` pool (2× NVMe mirror) will be the home for hot data —
databases, VM root disks, service metadata. Until that pool exists,
`tank` carries everything.

## Pool-level properties are general-purpose

Set at `zpool create` time:

| Property | Why |
|---|---|
| `ashift=12` | drive geometry, not workload |
| `compression=lz4` | universal small wins, free CPU |
| `atime=off` | universal IOPS save |
| `xattr=sa` + `acltype=posixacl` | modern Linux defaults |
| `normalization=formD` | universal Unicode hygiene |
| `dnodesize=auto` | required for xattr=sa to actually help |

None of these are media-specific. The only media-specific tuning is
`recordsize=1M` on `tank/media` and its children — a *dataset* property.
Everything else inherits the 128 KiB pool default, which is the right
value for almost anything that isn't bulk sequential reads.

## Adding a new workload

1. Create the dataset with a workload-appropriate `recordsize`:
   - **Bulk blobs (object storage, backups, archives)**: leave default (128 KiB).
   - **Databases**: match the page size (Postgres 8K, MySQL 16K, SQLite 4K).
     Better still: put databases on `fast` once it exists.
   - **VM disk images**: 16 KiB–64 KiB depending on guest filesystem.
2. Set `mountpoint=legacy` so NixOS owns the mount, not ZFS:
   ```
   sudo zfs create -o recordsize=128K tank/<name>
   sudo zfs set mountpoint=legacy tank/<name>
   ```
3. Add a `fileSystems` entry in `modules/nixos/zfs-tank.nix` (same pattern
   as the existing seven). Rebuild — the mount comes up under NixOS.
4. **Set quotas** before the second workload accumulates real data.
   Once `tank` has more than just media, cap big consumers so no one
   starves the rest:
   ```
   sudo zfs set quota=22T tank/media         # cap media
   sudo zfs set reservation=4T tank/objects  # guarantee object storage
   ```

## Gotchas worth knowing before adding a workload

- **Single vdev = single-disk random IOPS.** raidz2 stripes sequential
  reads but not random reads. Heavy random-read workloads (hot
  Prometheus tsdb, busy Postgres) feel this. Move those to `fast` when
  it exists, or accept the hit.
- **ZFS performance falls off above ~80% full.** All datasets slow
  together — not just the one that filled. Quotas keep one dataset from
  pushing the whole pool past the cliff.
- **Snapshot policy is per-dataset.** `modules/nixos/zfs-tank.nix`
  declares sanoid templates for the media + jellyfin paths. New
  workloads need their own template + dataset entry, or they don't
  get snapshotted.
- **`dedup=on` is still the wrong answer** at homelab scale, even with
  256 GB RAM. Compress, don't dedup.
- **Pool is never declarative.** Pool creation is the one-shot runbook
  at `docs/runbooks/zfs-pool-creation.md`. New *datasets* are imperative
  via `zfs create` (cheap and reversible — `zfs destroy <ds>` is fine).
  Only the *fileSystems* entries and snapshot policy go in nix.

## Currently on the pool

Datasets (`zfs list -r tank`):

- `tank/media`, `tank/media/movies`, `tank/media/tv` — Jellyfin source
  (recordsize=1M; weekly snapshots)
- `tank/jellyfin`, `tank/jellyfin/config`, `tank/jellyfin/cache` —
  Jellyfin state (recordsize=128K; aggressive snapshots on config)
- `tank/downloads` — qBittorrent landing zone (Phase 2; recordsize=128K)
