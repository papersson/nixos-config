{ config, lib, pkgs, ... }:

# Declarative, import-only half of the bulk-storage `tank` pool.
#
# The pool is general-purpose; media is the first tenant, not the only one.
# New workloads add a `fileSystems` entry below plus (if they need snapshots)
# a sanoid template + dataset entry. See `docs/storage.md` for the full
# dataset-creation pattern and quota guidance.
#
# The pool itself is created exactly once, imperatively, by
# `docs/runbooks/zfs-pool-creation.md`. This module never creates or
# modifies the pool — it only imports it, declares mount points, and
# runs ongoing maintenance (scrubs, snapshots). Safe to re-run on every
# reinstall. The single most important rule of a z840 reinstall is that
# `tank` is never reformatted: see `docs/runbooks/reinstall-from-bare-metal.md`.

{
  # Kernel + userspace ZFS support.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # Import the tank pool at boot.
  boot.zfs.extraPools = [ "tank" ];

  # SCT Error Recovery Control: tell each tank drive to give up on a bad
  # sector after 7.0 seconds and return an error to the kernel, instead of
  # hanging the SATA bus for 30+ seconds trying internal recovery. ZFS
  # reconstructs the data from raidz2 parity in milliseconds; we want the
  # drive to fail fast so ZFS can do its job. Setting is volatile — drives
  # reset to "Disabled" on every power cycle — so this runs once at boot,
  # before the pool is imported. wwn list mirrors the runbook bay table; if
  # a drive is replaced, update it here too.
  systemd.services.tank-drive-erc = {
    description = "Set SCT ERC=7.0s on tank drives (resets on power cycle)";
    wantedBy = [ "zfs-import.target" ];
    before = [ "zfs-import.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.smartmontools ];
    script = ''
      for d in /dev/disk/by-id/wwn-0x5000cca2a1e7ade9 \
               /dev/disk/by-id/wwn-0x5000cca2a1e805a2 \
               /dev/disk/by-id/wwn-0x5000cca2a1e7c8f3 \
               /dev/disk/by-id/wwn-0x5000cca284eb772f; do
        smartctl -l scterc,70,70 "$d"
      done
    '';
  };

  # Each dataset has `mountpoint=legacy` set during pool creation (see the
  # runbook). NixOS owns the mount points so they're declared in the flake
  # and systemd can derive service-to-mount dependencies automatically.
  # `tank/media` is a SINGLE dataset (no movies/tv/downloads children) on
  # purpose: nixarr's *arr import does an instant hardlink + atomic move from
  # the qBittorrent download dir (`/tank/media/qbittorrent`) into the library
  # (`/tank/media/library/...`), and hardlinks cannot cross ZFS datasets. One
  # dataset = one filesystem = hardlinks work, so an imported file seeds with
  # zero extra space. The cost is uniform recordsize=1M and that weekly
  # snapshots also cover in-progress torrents — both acceptable. `tank/nixarr`
  # holds the *arr SQLite state (pool-default 128K, snapshotted aggressively).
  fileSystems = {
    "/tank/media"           = { device = "tank/media";           fsType = "zfs"; };
    "/tank/nixarr"          = { device = "tank/nixarr";          fsType = "zfs"; };
    "/tank/jellyfin"        = { device = "tank/jellyfin";        fsType = "zfs"; };
    "/tank/jellyfin/config" = { device = "tank/jellyfin/config"; fsType = "zfs"; };
    "/tank/jellyfin/cache"  = { device = "tank/jellyfin/cache";  fsType = "zfs"; };
  };

  # Monthly scrubs catch silent bit-rot before it becomes data loss.
  # Default schedule (second Sunday of the month) is fine; empty `pools`
  # means "all imported pools" which today is just `tank`.
  services.zfs.autoScrub.enable = true;

  # Snapshot policy per `docs/media-server.md`:
  # - app-state datasets (tank/jellyfin/config, tank/nixarr): SQLite + small
  #   frequent writes — snapshot aggressively (hourly/daily/weekly).
  # - tank/media: bulk media + qBittorrent download dir, weekly only; raidz2
  #   covers drive loss, snapshots here only guard against accidental delete /
  #   corruption from above. Weekly cadence also sweeps up in-progress torrents,
  #   which is cheap and self-pruning at 4 weeks.
  # - tank/jellyfin/cache: not snapshotted (regenerable).
  services.sanoid = {
    enable = true;
    templates = {
      app-state = {
        hourly = 24;
        daily = 7;
        weekly = 4;
        autoprune = true;
        autosnap = true;
      };
      media-weekly = {
        weekly = 4;
        autoprune = true;
        autosnap = true;
      };
    };
    datasets = {
      "tank/jellyfin/config".useTemplate = [ "app-state" ];
      "tank/nixarr".useTemplate = [ "app-state" ];
      "tank/media".useTemplate = [ "media-weekly" ];
    };
  };
}
