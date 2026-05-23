# Boot SSD disk layout for z840, managed by disko.
#
# SCOPE: this file describes ONLY the OS/boot SSD. The 48 TB ZFS `tank` media
# pool is deliberately absent. tank is created once by hand and is import-only
# forever after; declaring it here would let `disko --mode destroy,format`
# wipe it. See docs/runbooks/reinstall-from-bare-metal.md and docs/media-server.md.
#
# Mirrors the current ext4-root + vfat-ESP layout (no LUKS, no subvolumes, no
# swap). ESP mount options match hardware-configuration.nix so the generated
# fileSystems config is semantically identical for validation.
{
  disko.devices.disk.boot = {
    type = "disk";

    # Boot SSD: Samsung 512 GB NVMe (currently nvme0n1), holding /boot + /.
    # The four 16 TB HC550s (WUH721816ALE6L4, currently sda-sdd) are the future
    # `tank` raidz1 members and must never be targeted here. by-id (model+serial)
    # is stable across reboots; /dev/nvme0n1 enumeration is not, and disko's
    # destroy mode is irreversible.
    device = "/dev/disk/by-id/nvme-SAMSUNG_MZVPV512HDGL-000H1_S27FNYAG601530";

    content = {
      type = "gpt";

      partitions = {
        ESP = {
          priority = 1;
          size = "1G";
          type = "EF00";

          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0022" "dmask=0022" ];
          };
        };

        root = {
          size = "100%";

          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
