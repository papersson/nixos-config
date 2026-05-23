# Concepts: disko, facter, and how a flake install actually works

Background for the runbooks in this directory. Read this once to build the mental
model; the runbooks assume it.

## The one idea that explains everything

A flake is **evaluated on one machine and the result runs on another** (or on the
same machine at a different time). Evaluation turns your `.nix` files into concrete
`/nix/store` artifacts: a disk-format script, a system closure, an activation script.
Those artifacts are self-contained. Nothing about evaluating the flake touches a
disk.

This separation resolves most "but how can that work before X exists" questions:

- You can evaluate the flake before the target disk is partitioned, because
  evaluation reads `.nix` files, not the disk.
- The flake never needs to live *on* the target disk first. It lives wherever you
  evaluate it (your laptop, the installer's RAM, a remote builder), and only the
  produced artifacts get copied onto the target once its filesystem exists.

## `hardware-configuration.nix` is doing two unrelated jobs

`nixos-generate-config` writes one file that mixes two concerns:

1. **Hardware detection.** `boot.initrd.availableKernelModules`, `kvm-intel`,
   microcode, `hostPlatform`. What this machine *is*.
2. **Disk layout.** The `fileSystems.*` mounts, `boot.initrd.luks.devices.*`, swap.
   How this machine's storage is *carved up*.

facter replaces job 1. disko replaces job 2 (and, more usefully, generates the
recipe to recreate the layout from scratch).

## disko

You describe the disk layout once, declaratively, in Nix: partitions, LUKS,
filesystems, btrfs subvolumes, swap. From that single source disko produces two
things:

- A **format/partition script** (`config.system.build.diskoScript`) that wipes a
  blank disk and recreates the exact layout, encryption included, in one command.
- The **runtime `fileSystems.*` / `boot.initrd.luks.*` config** NixOS needs at boot.

Because both come from the same spec, the "how to create it" and "how to mount it"
halves can't drift apart. Today neither host has a disko spec: the t14 layout exists
only as a *result* in `hosts/t14/hardware-configuration.nix` plus a *prose procedure*
in `reference.md` (the `cryptsetup` / `mkfs.btrfs` / `btrfs subvolume create` block).
That is documented, not reproducible. disko closes that gap.

Adopting disko is non-destructive. You write the spec, expose
`diskoConfigurations.<host>`, and validate it by diffing disko's generated
`fileSystems` against the current `hardware-configuration.nix`. The destructive
format script only ever runs on a fresh install.

## nixos-facter

Instead of a one-time `nixos-generate-config` snapshot, you run the `nixos-facter`
probe once to produce a `report.json` hardware inventory. The `nixos-facter-modules`
flake reads that JSON and derives `availableKernelModules`, microcode, and similar at
eval time, so the detection half stays accurate instead of going stale.

The honest caveat: for two known machines this is low payoff on its own, and facter's
asserted kernel modules can collide with the `nixos-hardware` `common-*` modules this
flake already imports. Its real value is as the partner to disko for a one-command
reinstall. Treat it as optional polish, not a priority.

## nixos-anywhere

A driver you run *from another machine* (your laptop) to install NixOS onto a remote
target over SSH. It kexecs the target into a RAM-backed installer if needed, copies
the disko script and system closure into the target's RAM, runs disko to format the
disk, then installs. The target's existing disk contents are irrelevant. It requires
a disko spec, since that is how it knows how to partition.

This is the natural fit for the headless z840: no monitor, no USB juggling, install
and reinstall from the laptop.

## Why "clone before mount" works

The official installer USB boots into a Linux running entirely in RAM, with a normal
writable filesystem (your home dir, `/tmp`). `git clone` writes there, into RAM. It
has nothing to do with the blank target disk, so the disk being unpartitioned never
blocks the clone. With disko you clone (or reference the flake) *first*, because the
config is what tells disko how to partition; then disko mounts the real disk; then you
install onto it.

## You usually don't need `git clone` at all

Nix has a git fetcher built in. `disko` and `nixos-install` both take a `--flake` ref
pointing straight at GitHub, and nix fetches it internally with no `git` CLI involved:

```
nixos-install --flake github:patrikpersson/nixos-config#z840
```

That sidesteps the question of whether `git` is on the installer (it is, on the
official ISO, but this avoids depending on it). If you ever do need a tool the
installer lacks, `nix shell nixpkgs#git` or `nix-shell -p git` summons it on demand,
since the installer always has `nix` and network.
