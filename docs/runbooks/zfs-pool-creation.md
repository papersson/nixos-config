# Create the `tank` ZFS pool on z840

One-shot creation of the bulk-storage pool that backs the media server (see
`docs/media-server.md`). Read `concepts.md` if the eval-vs-execution split or the
"data pools are import-only" rule isn't fresh.

## Status: not yet executed

This file is the recipe. The pool does not exist yet — Phase 0 step 3 of
`media-server.md`. Drives have completed burn-in (long SMART self-test) with zero
errors. Run this exactly once, then never again.

## The one rule

**The pool is created here, imperatively, by hand. It is never declarative, never in
disko, never in a NixOS module, and never re-run.** The declarative half — kernel
support, `boot.zfs.extraPools`, mount points, snapshot policy — lives in
`modules/nixos/zfs-tank.nix` and is *import-only*. The split is deliberate: a stray
`--mode destroy,format` on a declarative pool wipes 28 TB of irreplaceable data with
no offsite backup. The blast radius of formatting must be impossible to trigger from
a config change.

If you find yourself reading this file a second time, you are doing something wrong
or rebuilding from a real disaster. Most likely the latter — in which case the
correct command is `zpool import tank`, not anything below.

## Preflight

All of these must pass before `zpool create`. Each one's a 10-second check and
catches a real footgun.

### 1. Burn-in cleared

```
for d in a b c d; do echo "=== sd$d ==="; sudo smartctl -l selftest /dev/sd$d | tail -3; done
for d in a b c d; do echo "=== sd$d ==="; sudo smartctl -a /dev/sd$d | grep -E "Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable"; done
```

All four drives must show "Completed without error" with `-` in the LBA column, and
all three counters at 0. Anything else: stop, investigate; these are used drives so
RMA is not a path.

### 2. Firmware levels match across drives

```
for d in a b c d; do sudo smartctl -i /dev/sd$d | grep -E "Model|Firmware|Serial"; done
```

Mixed firmware in a vdev is not catastrophic but is avoidable. If they differ,
decide *now* whether to flash before pool create (easier than after).

### 3. TLER (error recovery timeout) sane

```
for d in a b c d; do echo -n "sd$d: "; sudo smartctl -l scterc /dev/sd$d | grep -E "Read|Write"; done
```

Should report ~70 (deciseconds = 7 s) for read and write on HC550 by default.
Enterprise WD drives ship with this set sensibly; the check is just confirmation.

### 4. `networking.hostId` is set

```
hostname; cat /etc/machine-id; grep hostId /home/patrikpersson/nixos-config/hosts/z840/default.nix
```

ZFS stamps the pool with the creating host's `hostId` and refuses to import a pool
owned by a different id without `-f`. The flake pins `networking.hostId =
"8f3a1c2b"` for exactly this reason — keeps the pool importable across reinstalls.
If this is missing, fix it and rebuild before creating the pool.

### 5. Record the wwn → serial → bay mapping

Write this to `docs/z840-drive-bays.md` or wherever you'll find it under stress.
`wwn-*` ids are stable but human-unreadable; the mapping is what lets you yank the
right caddy when a drive fails.

```
for d in a b c d; do
  wwn=$(ls -l /dev/disk/by-id/ | awk -v t="../../sd$d" '$NF == t && /wwn-/ {print $(NF-2)}')
  serial=$(sudo smartctl -i /dev/sd$d | awk -F: '/Serial Number/ {gsub(/ /,"",$2); print $2}')
  echo "sd$d  $wwn  $serial"
done
```

Today the mapping is:

| Bay        | Linux | wwn (stable)              | Serial    | P/N     | Mfg date    |
|------------|-------|---------------------------|-----------|---------|-------------|
| Upper      | sda   | wwn-0x5000cca2a1e7ade9    | 2CJU8YPN  | 0F38466 | 12 Apr 2021 |
| 2nd Upper  | sdb   | wwn-0x5000cca2a1e805a2    | 2CJV1A3N  | 0F38466 | 18 Apr 2021 |
| 3rd        | sdc   | wwn-0x5000cca2a1e7c8f3    | 2CJUJ4ZN  | 0F38466 | 18 Apr 2021 |
| Bottom     | sdd   | wwn-0x5000cca284eb772f    | 3WK2M50P  | 0F38485 | 05 Mar 2021 |

Notes:
- `sda`–`sdd` ordering can change across reboots and HBA reseats — `wwn-*` cannot.
  From here on, use the `wwn-*` paths.
- The bottom drive is a different P/N (`0F38485` vs `0F38466` on the other three)
  and from an earlier production run. Probably a minor HC550 revision; mildly good
  news for batch-correlation risk.
- When a drive fails in the future, `zpool status tank` reports the `wwn-*` id.
  Look it up in this table to know which physical bay to pull.

## Create the pool

Dry-run first. This validates the command without touching disks.

```
sudo zpool create -n \
  -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O normalization=formD \
  -O dnodesize=auto \
  tank raidz2 \
  /dev/disk/by-id/wwn-0x5000cca2a1e7ade9 \
  /dev/disk/by-id/wwn-0x5000cca2a1e805a2 \
  /dev/disk/by-id/wwn-0x5000cca2a1e7c8f3 \
  /dev/disk/by-id/wwn-0x5000cca284eb772f
```

Read the output carefully. Confirm:
- All four drives listed.
- Layout shows `raidz2`, not `raidz1` or four separate vdevs.
- No "device is in use" / partition table warnings.

Then drop the `-n` and run for real:

```
sudo zpool create \
  -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O normalization=formD \
  -O dnodesize=auto \
  tank raidz2 \
  /dev/disk/by-id/wwn-0x5000cca2a1e7ade9 \
  /dev/disk/by-id/wwn-0x5000cca2a1e805a2 \
  /dev/disk/by-id/wwn-0x5000cca2a1e7c8f3 \
  /dev/disk/by-id/wwn-0x5000cca284eb772f
```

Why each property:

| Property | Reason |
|---|---|
| `ashift=12` | 4 KiB allocation alignment. HC550 reports 4096 physical via sysfs. Immutable per vdev — get it right now. |
| `compression=lz4` | Effectively free CPU, frequent space win on text/metadata, and lossless on already-compressed media. Default resolves to lz4 anyway; setting it explicitly is self-documenting. |
| `atime=off` | Reading a file shouldn't write metadata. Saves IOPS on every read. |
| `xattr=sa` | Stores extended attributes inline in the dnode instead of as hidden directory entries. Big win for POSIX ACLs / Samba / SELinux. |
| `acltype=posixacl` | Linux POSIX ACL semantics; pairs with `xattr=sa`. |
| `normalization=formD` | **Cannot be changed after dataset creation.** Makes filenames canonical NFD so Unicode-equivalent strings compare equal. Cheap insurance for media filenames with accents. |
| `dnodesize=auto` | Required to realize the `xattr=sa` benefit; default is still `legacy`. |
| (no `recordsize` at pool level) | Pool root keeps the 128 KiB default. `tank/media` will explicitly set 1M (below); other datasets inherit the default. |

## Create the datasets

```
sudo zfs create -o recordsize=1M tank/media
sudo zfs create tank/media/movies
sudo zfs create tank/media/tv

sudo zfs create tank/jellyfin
sudo zfs create tank/jellyfin/config
sudo zfs create tank/jellyfin/cache

sudo zfs create tank/downloads
```

`recordsize=1M` is set on `tank/media` so it cascades to `movies` and `tv`. The
`jellyfin` and `downloads` trees inherit the pool's default 128 KiB, which is right
for SQLite (small random writes) and BitTorrent (random sequential).

## Verify

```
zpool status tank
zpool list -v tank
zfs list -r tank
zfs get -r compression,atime,xattr,acltype,normalization,dnodesize,recordsize tank
sudo zdb -C tank | grep -E "ashift|name:"
```

Sanity check:
- `zpool status` shows all four drives `ONLINE`, no errors, state `ONLINE`.
- `zpool list -v` shows the `wwn-*` ids (not `sda`–`sdd`).
- `zfs list` shows seven datasets under `tank/`.
- `zfs get` confirms inherited properties (especially `recordsize=1M` on
  `tank/media*`, `128K` elsewhere).
- `zdb -C` confirms `ashift: 12`.

## Write a test file (while ZFS auto-mounts are still in place)

```
sudo install -d -o patrikpersson -g users /tank/media/movies/_test
echo "smoke test $(date)" > /tank/media/movies/_test/hello.txt
cat /tank/media/movies/_test/hello.txt
rm /tank/media/movies/_test/hello.txt && rmdir /tank/media/movies/_test
```

If write/read/delete all succeed, the pool is healthy.

## Hand over mount management to NixOS

By default, ZFS auto-mounts each dataset at `/<dataset-name>` via the
`zfs-mount.service`. The flake's `modules/nixos/zfs-tank.nix` declares the same
mount points as `fileSystems` entries so they're visible in the config and
systemd can derive service-to-mount dependencies. To avoid a double-mount
fight between the two systems, set `mountpoint=legacy` on each dataset so ZFS
stops trying to mount them:

```
for ds in \
  tank/media tank/media/movies tank/media/tv \
  tank/jellyfin tank/jellyfin/config tank/jellyfin/cache \
  tank/downloads; do
  sudo zfs set mountpoint=legacy "$ds"
done
```

After this, `zfs list` will show `legacy` in the MOUNTPOINT column for each
dataset, and `mount | grep tank` will be empty until NixOS mounts them on the
next activation.

## Activate the declarative side

The pool exists but nothing is mounted. The flake already contains
`modules/nixos/zfs-tank.nix` (imported from `hosts/z840/default.nix`) with the
`fileSystems` entries, `boot.zfs.extraPools = [ "tank" ]`, sanoid snapshot
policy, and monthly scrub.

```
nh os switch
```

After the rebuild, verify everything came up:

```
mount | grep tank
systemctl status zfs-mount sanoid.timer zfs-scrub.timer
zpool status tank
```

You should see seven `tank/*` lines in `mount`, all green systemd units, and
`zpool status` reporting `ONLINE` with no errors. From this point on the pool
is import-only — never touch `zpool create` on this host again. Subsequent
reboots and reinstalls bring the pool back via the declarative path.

## Footguns to never do

- **`zpool create -f`** — `-f` overrides "device is in use" and "device contains
  existing filesystem." If `create` complains, find out *why* before forcing.
- **`zpool destroy tank`** — exactly what it says. No undo.
- **`zfs destroy -r tank`** — recursive destroy of the entire dataset tree.
- **Adding `dedup=on`** anywhere — fashionable, expensive forever, basically never
  the right answer at homelab scale.
- **Putting `tank` in disko** — see `reinstall-from-bare-metal.md`. The pool stays
  out of every `--mode destroy,format` codepath, always.
- **Re-running this runbook** on a host where `tank` already exists. Import,
  don't create.
