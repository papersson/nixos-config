# Reinstall a host from bare metal

How to bring a host back from a blank disk: dead SSD, new machine, or a clean
reinstall. Read `concepts.md` first if the eval-vs-execution split isn't fresh.

## Status: disko not wired up yet

The clean flow below depends on a `hosts/<host>/disko.nix` and a
`diskoConfigurations.<host>` output, **neither of which exists yet**. Until those are
written:

- **t14**: follow the manual procedure in `reference.md` (the `cryptsetup` /
  `mkfs.btrfs` / `btrfs subvolume create` / `mount` block). It is the source of truth
  for the current layout.
- **z840**: simple enough (ext4 root + vfat ESP, no LUKS, no subvolumes) to either
  redo by hand or write a ~15-line disko spec first. The simplest place to start
  adopting disko.

Treat the rest of this file as the target procedure, and as the spec for what the
disko work needs to produce.

## What each host's disk looks like

- **t14** (`hosts/t14/hardware-configuration.nix`): GPT, 1 GiB vfat ESP at `/boot`,
  LUKS2 (argon2id) container `cryptroot`, btrfs inside it with subvolumes `@` `@home`
  `@nix` `@persist` `@snapshots` `@swap`. Mount options
  `noatime,compress=zstd:1,ssd,discard=async,space_cache=v2`, plus a 16 GiB swapfile
  under `@swap`. `@persist` exists but impermanence is not enabled.
- **z840** (`hosts/z840/hardware-configuration.nix`): ext4 root on a single partition,
  vfat ESP at `/boot`, no encryption, no subvolumes, no swap device.

## Data pools are import-only, never reformatted

The z840 will gain a separate ZFS pool `tank` (4x HC550 16 TB raidz1, ~48 TB) for the
media library (see `media-server.md`). It is not part of any host's OS disk, and the
single most important rule of a z840 reinstall is:

**`tank` must never appear in a disko spec or any `--mode destroy,format` command.**

A pool survives OS reinstalls. You reformat the boot SSD and re-import the untouched
pool. The data is irreplaceable and there is no offsite backup in early phases, so the
blast radius of formatting it is total.

- `tank` is created exactly once, by hand (`zpool create ...`), and is import-only
  forever after. Pool creation is never declarative and never in disko (see the Phase 0
  boundary in `media-server.md`).
- On reinstall, once the OS is up, import the existing pool: `zpool import tank`.
- **`networking.hostId` is load-bearing.** ZFS stamps the pool with the creating host's
  `hostId` and refuses to import a pool owned by a different id without `-f`. A fresh
  install generates a new random `hostId`, which would block the import. z840 pins
  `networking.hostId = "8f3a1c2b"` (`hosts/z840/default.nix`) precisely so it stays
  stable across reinstalls. The bootstrap config you install with must already set this
  hostId before you attempt `zpool import`, or the import refuses and you reach for `-f`
  on a 48 TB pool at the worst possible moment.

## Path A: local install from the installer USB

For the t14, or the z840 with a monitor attached.

1. Boot the **official minimal NixOS installer USB**. It runs from RAM.
2. Get networking up (wired is automatic; for Wi-Fi use `wpa_supplicant` or `iwctl`).
3. Partition, format, and mount. Two options:
   - **With disko** (once the spec exists), one command does all of it:
     ```
     nix --extra-experimental-features "nix-command flakes" \
         run github:nix-community/disko -- \
         --mode destroy,format,mount \
         --flake github:patrikpersson/nixos-config#t14
     ```
   - **Without disko** (today), follow the manual block in `reference.md`.
4. Install, pulling the flake straight from GitHub (no clone needed):
   ```
   nixos-install --flake github:patrikpersson/nixos-config#t14
   ```
5. Set the root password when prompted, reboot, remove the USB.

Cloning the repo is only necessary if you want to edit the config on the box before
installing (for example to regenerate hardware detection). If so, clone into the
installer's RAM home dir and use `--flake .#t14`.

## Path B: remote install with nixos-anywhere (z840)

Preferred for the headless z840: drive it from the t14, no monitor needed. The target
must be reachable over SSH, either already running some Linux or booted into any
installer with an SSH daemon. Requires the disko spec.

From the laptop:
```
nix --extra-experimental-features "nix-command flakes" \
    run github:nix-community/nixos-anywhere -- \
    --flake github:patrikpersson/nixos-config#z840 \
    root@<z840-ip>
```

nixos-anywhere kexecs the target into a RAM installer if needed, runs disko to format
the disk, copies the closure, and installs. The target's old disk contents are wiped.

## After install: secrets

Secrets are not restored by the install. sops-nix decrypts at activation using a key
the new machine must already hold.

- **t14**: `secrets/t14.yaml` (Wi-Fi PSK, user SSH key) is encrypted to the user age
  key and the host age key. A fresh install has a new host SSH key, so its derived age
  recipient won't match. Either restore the old host key, or run
  `sops updatekeys secrets/t14.yaml` after adding the new host's recipient to
  `.sops.yaml`, then commit. Without this, activation fails to decrypt.
- **z840**: no sops secrets *yet*. Media-server Phase 2 adds `secrets/z840.yaml`
  (Mullvad WireGuard key, *arr API keys). Once it exists, the same host-key gotcha
  applies symmetrically: a fresh install's new host SSH key won't match the recipient
  `z840.yaml` was encrypted to, so restore the old host key or
  `sops updatekeys secrets/z840.yaml` after updating `.sops.yaml`.

See the secrets conventions in `CLAUDE.md` and `.sops.yaml` for the recipient list.

## Escape hatches

- A tool seems missing on the installer: `nix shell nixpkgs#git` or
  `nix-shell -p <tool>`. The installer always has `nix` and network.
- A switch left the system unbootable: pick an older generation in the bootloader, or
  from a rescue shell `nixos-rebuild switch --rollback`.
- On t14 you can unlock and mount the btrfs root from an initrd or live shell to
  repair config in place rather than reinstalling.

## TODO to make this real

1. Write `hosts/z840/disko.nix` from its current `hardware-configuration.nix` (easy:
   ext4 + vfat, no LUKS). Scope it to the **boot SSD only**: the `tank` pool stays out
   of it (see "Data pools are import-only" above). Expose `diskoConfigurations.z840`.
   Validate by diffing generated `fileSystems` against the existing file. This also
   unlocks Path B.
2. Write `hosts/t14/disko.nix` (LUKS2 + btrfs subvolumes) once the z840 spec has
   proven the workflow.
3. Optional: adopt nixos-facter (`report.json` per host) to replace the detection half
   of `hardware-configuration.nix`. Watch for conflicts with the `nixos-hardware`
   `common-*` modules.
