{ config, lib, pkgs, ... }:

# Declarative, import-only half of the bulk-storage `tank` pool.
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
  fileSystems = {
    "/tank/media"          = { device = "tank/media";          fsType = "zfs"; };
    "/tank/media/movies"   = { device = "tank/media/movies";   fsType = "zfs"; };
    "/tank/media/tv"       = { device = "tank/media/tv";       fsType = "zfs"; };
    "/tank/jellyfin"       = { device = "tank/jellyfin";       fsType = "zfs"; };
    "/tank/jellyfin/config" = { device = "tank/jellyfin/config"; fsType = "zfs"; };
    "/tank/jellyfin/cache"  = { device = "tank/jellyfin/cache";  fsType = "zfs"; };
    "/tank/downloads"      = { device = "tank/downloads";      fsType = "zfs"; };
  };

  # Monthly scrubs catch silent bit-rot before it becomes data loss.
  # Default schedule (second Sunday of the month) is fine; empty `pools`
  # means "all imported pools" which today is just `tank`.
  services.zfs.autoScrub.enable = true;

  # Snapshot policy per `docs/media-server.md`:
  # - tank/jellyfin/config: SQLite + plugins, frequent small writes — snapshot aggressively.
  # - tank/media (recursive): bulk media, weekly only; raidz2 covers drive loss, snapshots
  #   here only protect against accidental delete / corruption from above.
  # - tank/jellyfin/cache, tank/downloads: not snapshotted (regenerable / churn).
  services.sanoid = {
    enable = true;
    templates = {
      jellyfin-config = {
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
      "tank/jellyfin/config".useTemplate = [ "jellyfin-config" ];
      "tank/media" = {
        useTemplate = [ "media-weekly" ];
        recursive = true;
      };
    };
  };
}
