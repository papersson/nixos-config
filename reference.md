# NixOS on a refurbished T14 Gen 4 Intel — a consultant's second machine

## 1. Background

Nix is a purely functional package manager: every package is a *derivation* (a content-addressed build recipe) that produces a path in `/nix/store/<hash>-<name>` whose hash covers every input. NixOS is the Linux distribution built on top, where the entire system — kernel, services, user environment — is a single derivation produced by evaluating a Nix expression. The fact that build inputs are referentially transparent is what makes the rest work: two evaluations of the same expression on the same inputs produce the same store path, and the store path is the system.

**Generations and atomic switching.** Each `nixos-rebuild switch` builds a new system derivation, links it as a new generation under `/nix/var/nix/profiles/system-<N>-link`, and atomically swaps the running configuration. Rollback is just selecting an older generation at boot or via `--rollback`. The bootloader entry list is itself a function of the generation set. There is no in-place upgrade, only side-by-side new builds. See the NixOS manual at <https://nixos.org/manual/nixos/stable/>.

**Flakes** turn a project (or a system configuration) into a value with **pinned inputs** (`flake.lock`) and **named outputs** (`nixosConfigurations.<name>`, `devShells.<system>.<name>`, …). Before flakes, channel state was a per-machine ambient parameter living in `~/.nix-channels`; with flakes that state is hoisted into the repository as `flake.lock`. The lockfile is a hash-pinned snapshot of every input flake, so `nixos-rebuild --flake .#t14` on two machines, six months apart, evaluates against the same nixpkgs revision. nix.dev still describes flakes as experimental (`experimental-features = nix-command flakes`); in practice they are the de-facto standard for any multi-host configuration (<https://nix.dev/concepts/flakes.html>, <https://wiki.nixos.org/wiki/Flakes>).

**The module system** is the way NixOS configurations are composed. A module is a function `{ config, lib, pkgs, ... }: { options = …; config = …; imports = …; }`. Options have types (`mkOption { type = types.path; default = …; }`), modules can `mkDefault`/`mkForce`/`mkIf`, and the evaluator merges everything into one fixed-point `config` value. This is what lets `nixos-hardware`, `home-manager`, `sops-nix`, and your own modules cooperate without explicit ordering.

**home-manager** ([nix-community/home-manager](https://github.com/nix-community/home-manager)) is a separate module system for **user-scoped** state: dotfiles, `~/.ssh/config`, `programs.firefox.profiles`, GTK theme, shell, editor. It can run standalone (`home-manager switch`) or as a NixOS module evaluated inside the system rebuild. The system module is recommended when the user is on NixOS and only on NixOS — one command rebuilds and rolls back system + user together, and HM modules can read `osConfig`. Standalone HM is for managing user state on Darwin or non-NixOS Linux from the same flake.

**nixos-hardware** ([NixOS/nixos-hardware](https://github.com/NixOS/nixos-hardware)) is a collection of opt-in NixOS modules with vendor- and model-specific defaults: microcode loading, kernel modules for fingerprint readers, sane TLP profiles, suspend quirks. You import the closest matching profile and override what you don't like. Important fact established below: there is **no `lenovo-thinkpad-t14-intel-gen4` module** in upstream nixos-hardware as of May 2026, so you compose from the generic `common/*` modules.

For an orientation paragraph against other distributions: NixOS replaces `apt`/`dnf`/`pacman` with derivations, replaces `/etc` editing with module evaluation, and replaces "upgrade" with "build the next generation." If you have used Guix you already have the mental model. Everything else in this guide assumes you understand monadic configuration evaluation, lazy attrset merges, and the idea that the system is a value.

## 2. Hardware considerations for the T14 Gen 4 Intel

Everything works on a recent kernel; almost nothing **only** works because of a nixos-hardware module. The list below tracks the components that actually need attention.

**No dedicated nixos-hardware profile exists for this model.** Inspecting the upstream `flake.nix` confirms only `lenovo-thinkpad-t14-intel-gen1`, `lenovo-thinkpad-t14-intel-gen1-nvidia`, and `lenovo-thinkpad-t14-intel-gen6` for Intel T14s; AMD Gen 1–5 exist, but Gen 2/3/4/5 Intel are absent (<https://github.com/NixOS/nixos-hardware/blob/master/flake.nix>). The pragmatic recipe is to compose `common-pc-laptop`, `common-pc-ssd`, `common-cpu-intel`, `common-gpu-intel`, plus the generic `lenovo/thinkpad` common module. PR #1572 added Gen 6 (<https://github.com/NixOS/nixos-hardware/pull/1572>) — the same pattern would apply for an eventual Gen 4 Intel contribution.

**What the composed modules set automatically.** Intel microcode (`hardware.cpu.intel.updateMicrocode = true`), `intel_pstate`, mesa/`intel-media-driver`, `services.fstrim.enable`, `services.thermald.enable` on the Intel branch, `services.tlp.enable` defaults via the laptop module, `hardware.trackpoint.enable`, and the `thinkpad_acpi` kernel module.

**What still needs explicit configuration.**

- **Synaptics fingerprint reader** (USB ID `06cb:00bd` or successor — Synaptics Prometheus / WBF match-on-chip): `services.fprintd.enable = true;` plus PAM wiring. The in-tree libfprint `synaptics` driver handles it; **do not enable `services.fprintd.tod`** (that is for older 138a:00xx Validity sensors and will break enrollment). Firmware updates over LVFS via `fwupd`. References: <https://github.com/fwupd/firmware-lenovo/issues/358>, <https://fprint.freedesktop.org/supported-devices.html>.
- **Intel Iris Xe iGPU**: needs `intel-media-driver` and `vpl-gpu-rt` for VA-API/oneVPL, plus `LIBVA_DRIVER_NAME=iHD`. The composed nixos-hardware module sets only the mesa baseline; QSV and oneVPL require the explicit add. See <https://wiki.nixos.org/wiki/Intel_Graphics>.
- **Intel AX211 Wi-Fi 6E + Bluetooth**: needs `hardware.enableRedistributableFirmware = true;` (or `enableAllFirmware = true;` if your closure tolerates the unfree blobs). Works on kernel ≥ 6.5; pinning `boot.kernelPackages = pkgs.linuxPackages_latest;` reduces the firmware-mismatch class of bugs. See <https://discourse.nixos.org/t/how-to-use-latest-iwlwifi-firmware-from-linux-firmware/15395>.
- **TrackPoint and touchpad**: handled by `services.libinput`; the only practical tunables are tap-to-click, palm rejection, and natural scrolling. **Wake-from-suspend** on TrackPoint nudges is a real problem on the T14 chassis family and is fixed with a `services.udev.extraRules` entry disabling `power/wakeup` on the I2C device.
- **s2idle suspend on Raptor Lake**: S3 deep sleep is **not available** on this generation — Modern Standby (s2idle) is the only option, exposed in `/sys/power/mem_sleep`. This is platform behavior, not a NixOS bug. Idle drain on closed lid is acceptable on stock kernel (~1%/hr in the field reports). Confirmed independently at <https://julianyap.com/pages/2024-10-31-1730430246/> and <https://blog.wirelessmoves.com/2023/11/lenovo-t14-gen-4-intel-suspend-resume-surprises-part-4.html>.
- **Fan and thermal**: stock `thermald` covers Raptor Lake DPTF tables. `thinkfan` is unnecessary on Gen 4 (BIOS-managed fan curve is sane); `throttled` was for pre-Tiger Lake CPUs with the IccMax bug and is not needed.
- **Brightness and Fn keys**: visible to `wev`, routed through `acpid` and `systemd-logind`. Under GNOME/KDE this is automatic; under Hyprland/Sway you must bind `XF86MonBrightness{Up,Down}` to `brightnessctl` explicitly because `programs.hyprland.enable` does not install `brightnessctl` (<https://github.com/NixOS/nixpkgs/issues/378681>).
- **BIOS via fwupd / LVFS**: the device entry is `com.lenovo.ThinkPadN3HET.firmware`; `services.fwupd.enable = true;` is the only NixOS-side requirement. Confirmed shipping versions in the 1.43→1.44+ range (<https://github.com/fwupd/firmware-lenovo/issues/433>) and the "Boot Order Lock disabled" prerequisite in <https://bbs.archlinux.org/viewtopic.php?id=298467>.
- **USB4 / Thunderbolt 4**: enable `services.hardware.bolt.enable = true;` and leave BIOS Thunderbolt security at "User Authorization." Hotplug occasionally drops dock-side USB after replug; the workaround is `echo 1 > /sys/bus/pci/devices/<id>/remove; echo 1 > /sys/bus/pci/rescan` and a kernel ≥ 6.12.
- **TPM 2.0**: BIOS exposes Intel PTT (firmware TPM); enable in firmware and add `security.tpm2.enable = true;` if you intend TPM-backed LUKS unlock.

**Day-one storage swap.** The T14 Gen 4 Intel has a **single M.2 2280 PCIe 4.0 ×4 slot** (the WWAN slot is M.2 2242, electrically unsuitable for normal NVMes). Memory is **soldered** on Gen 4 Intel — there is no SODIMM to upgrade. The 256 GB → 2 TB swap is therefore a one-shot operation on the only user-serviceable storage component. Treat it as a reproducibility milestone (see §4).

## 3. Pre-install checklist

**BIOS settings** (Enter → F1 at boot):

| Setting | Value | Reason |
|---|---|---|
| Supervisor Password | **Set one** | Required before Secure Boot keys can be manipulated on Lenovo firmware |
| Secure Boot | **Disabled** for first install; will be re-enabled with Lanzaboote later | NixOS installs through `systemd-boot` initially |
| Intel VT-x / VT-d | Enabled | KVM, IOMMU, microvm.nix at Level 4 |
| TPM 2.0 / Intel PTT | Enabled | LUKS2 TPM unlocking, measured boot |
| Boot Order Lock | **Disabled** | `fwupdmgr update` fails silently if locked |
| UEFI / CSM | UEFI only | Capsule firmware updates require pure UEFI |
| Sleep state | (Modern Standby only — no toggle) | S3 not available on Raptor Lake |
| Thunderbolt security | User Authorization | Pairs with `services.hardware.bolt` |

Source for the Boot Order Lock interaction: <https://bbs.archlinux.org/viewtopic.php?id=298467>; for Secure Boot prerequisites on Lenovo: <https://github.com/nix-community/lanzaboote/blob/master/docs/getting-started/enable-secure-boot.md>.

**BIOS update from the live ISO.** The minimal ISO does not ship `fwupd`; bring it in via `nix-shell`. Do this **before** installing — capsule updates are easier when the disk is empty.

```bash
sudo -i
loadkeys us
# Connect Wi-Fi via iwctl first; then:
nix-shell -p fwupd
fwupdmgr refresh --force
fwupdmgr get-devices
fwupdmgr get-updates
fwupdmgr update           # cold-reboots into capsule; keep AC plugged
```

**SSD swap.** Per the T14 Gen 4 / P14s Gen 4 Hardware Maintenance Manual: power off, unplug AC, **disable the built-in battery in BIOS** (Config → Power → Disable Built-in Battery — the laptop powers down), loosen the **seven captive Phillips #1 screws** on the base cover, pry from the rear hinge edge with a plastic spudger. Remove the single nylon-coated M2 × 2.5 mm retention screw on the M.2 2280 slot, slide the SSD out at ~20°, insert the new drive, refit screw at 0.18 Nm, refit cover. Reapply or retain the existing thermal pad — do not stack pads. Reconnect AC to re-enable the battery automatically.

**Data backup.** This is a fresh machine, so the only "data" to preserve is whatever Lenovo factory partition you may want to keep (most refurbs ship without one). The reproducibility argument later in §4 assumes you treat the laptop as disposable from day one — push your dotfile flake to a private git remote before powering it off.

## 4. Installation procedure

NixOS **25.11 "Xantusia"** is the current stable release as of May 2026 (released 2025-11-30; supported until ~2026-06-30 per the six-month policy at <https://nixos.org/blog/announcements/2025/nixos-2511/>). 25.05 reached EOL on 2025-12-31. Use 25.11 unless you have a reason not to.

Grab the minimal ISO from <https://nixos.org/download/> (canonical URL auto-resolves to the latest 25.11 build) and write it to USB:

```bash
sha256sum nixos-minimal-25.11.*-x86_64-linux.iso
sudo dd if=nixos-minimal-25.11.*.iso of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct
sync
```

Boot it. Then:

```bash
sudo -i
loadkeys us
systemctl start iwd
iwctl
# > device list / station wlan0 scan / station wlan0 connect <SSID> / exit
ping -c 3 cache.nixos.org
```

**Partitioning** (1 GiB ESP — large enough for many UKIs later, the rest LUKS2):

```bash
DISK=/dev/nvme0n1
wipefs -a "$DISK"; sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP   "$DISK"
sgdisk -n2:0:0   -t2:8309 -c2:CRYPT "$DISK"   # 8309 = Linux LUKS
partprobe "$DISK"
```

**LUKS2 with argon2id + 4 KiB sector** (matches NVMe page size and reduces write amplification):

```bash
cryptsetup luksFormat --type luks2 \
  --cipher aes-xts-plain64 --key-size 512 --hash sha512 \
  --pbkdf argon2id --sector-size 4096 --label NIXOS_LUKS \
  /dev/nvme0n1p2
cryptsetup open --allow-discards /dev/nvme0n1p2 cryptroot
mkfs.fat -F32 -n ESP /dev/nvme0n1p1
mkfs.btrfs -L nixos /dev/mapper/cryptroot
```

**Subvolumes.** The conventional layout (`@`, `@home`, `@nix`, `@persist`, `@snapshots`) is documented at <https://nixos.wiki/wiki/Btrfs> and used in essentially every modern community config. Create `@persist` now even though we are **not** enabling impermanence on day one — that keeps the door open without re-partitioning.

```bash
mount -o noatime /dev/mapper/cryptroot /mnt
for sv in @ @home @nix @persist @snapshots @swap; do
  btrfs subvolume create /mnt/$sv
done
umount /mnt

OPTS="noatime,compress=zstd:1,ssd,discard=async,space_cache=v2"
DEV=/dev/mapper/cryptroot
mount -o $OPTS,subvol=@           $DEV /mnt
mkdir -p /mnt/{boot,home,nix,persist,.snapshots,swap}
mount -o $OPTS,subvol=@home       $DEV /mnt/home
mount -o $OPTS,subvol=@nix        $DEV /mnt/nix
mount -o $OPTS,subvol=@persist    $DEV /mnt/persist
mount -o $OPTS,subvol=@snapshots  $DEV /mnt/.snapshots
mount -o noatime,subvol=@swap     $DEV /mnt/swap
chattr +C /mnt/swap                           # NOCOW required for swapfiles
btrfs filesystem mkswapfile --size 16g /mnt/swap/swapfile
swapon /mnt/swap/swapfile
mount -o umask=0077 /dev/nvme0n1p1 /mnt/boot
```

**Generate hardware config, then install from a flake from day one:**

```bash
nixos-generate-config --root /mnt
rm /mnt/etc/nixos/configuration.nix     # we will use the flake's
export NIX_CONFIG="experimental-features = nix-command flakes"

nix-shell -p git
git clone https://github.com/<you>/nixos-config /mnt/etc/nixos
# (Or scaffold from the skeleton in §5 below.)
# Move the generated hardware-configuration.nix into hosts/t14/.

nixos-install --no-root-passwd --flake /mnt/etc/nixos#t14
nixos-enter --root /mnt -c 'passwd <you>'
umount -R /mnt; swapoff -a; cryptsetup close cryptroot
reboot
```

The flake URI `#t14` resolves to `nixosConfigurations.t14`. The official chapter is at <https://nixos.org/manual/nixos/stable/index.html#sec-installation>.

**The 256 GB → 2 TB workflow.** Two orderings are plausible. **Install on the 256 GB drive first, then re-install on the 2 TB when it arrives** is the recommendation. The duplicated installation is a deliberate reproducibility self-test: your flake must produce a byte-identical system on a different drive size from the same `flake.lock`. If it doesn't, you have impurity to fix. Use `nix store diff-closures /run/current-system /run/booted-system` after the second install to confirm. Only `/home` and any state genuinely not declared (Syncthing DB, browser caches, SSH/GPG private material restored from your offline backup) should differ. The alternative — wait, swap, install once — saves about an hour but skips the most valuable lesson NixOS has to offer.

## 5. Flake repository structure

**Vanilla flakes vs flake-parts.** flake-parts ([hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)) applies the NixOS module system to `flake.nix` itself, eliminating `forAllSystems` boilerplate and giving you typed flake modules. It earns its keep with ≥3 systems × ≥3 outputs or when you publish reusable flake modules. For two hosts with one user and one architecture, vanilla flakes with a tiny `mkHost` helper is the boring consensus — what Misterio77, hlissner, and the starter templates use. **Default: vanilla.** Migrating to flake-parts later when a third host or `darwinConfigurations` appears is a half-hour mechanical refactor.

**home-manager as a NixOS module, not standalone.** Single `nixos-rebuild switch` for system + user, atomic rollback together, `osConfig` accessible from HM. Standalone wins only when you also manage HM on Darwin or a non-NixOS host — not the case here.

**Directory skeleton.**

```
.
├── flake.nix
├── flake.lock
├── .sops.yaml
├── hosts/
│   ├── t14/
│   │   ├── default.nix
│   │   ├── hardware-configuration.nix
│   │   └── disko.nix                  # optional; deferred (see §7)
│   └── server/
│       ├── default.nix                # placeholder
│       └── hardware-configuration.nix
├── modules/
│   ├── nixos/
│   │   ├── default.nix                # imports siblings
│   │   ├── common.nix                 # both hosts
│   │   ├── users.nix
│   │   ├── desktop.nix                # opt-in via my.desktop.enable
│   │   ├── thinkpad-t14-gen4.nix      # hardware bundle (§6)
│   │   └── isolation/                 # §10
│   │       ├── containers-acme.nix
│   │       └── microvm-acme.nix
│   └── home-manager/
│       ├── default.nix
│       ├── shell.nix
│       └── git.nix
├── home/
│   └── patrikpersson/
│       ├── default.nix
│       ├── programs.nix
│       └── firefox.nix
├── lib/
│   └── default.nix                    # mkHost
├── overlays/
│   └── default.nix                    # exposes pkgs.stable, custom pkgs
└── secrets/
    ├── common.yaml
    ├── laptop.yaml
    └── server.yaml
```

**Production-shaped `flake.nix`** (evaluatable against nixpkgs `nixos-25.11` as of May 2026):

```nix
{
  description = "Persson Tech AB — NixOS hosts (t14 + server)";

  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # microvm.nix lives in §10 (Level 4) — wire when escalating.
    # microvm = { url = "github:microvm-nix/microvm.nix"; inputs.nixpkgs.follows = "nixpkgs"; };

    systems.url = "github:nix-systems/default-linux";
  };

  outputs =
    { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware
    , sops-nix, lanzaboote, systems, ... } @ inputs:
    let
      inherit (nixpkgs) lib;
      forEachSystem = f: lib.genAttrs (import systems) f;

      mkHost = { hostname, system ? "x86_64-linux", users ? [], extraModules ? [] }:
        lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs self; };
          modules = [
            ./hosts/${hostname}
            ./modules/nixos
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs    = true;     # share nixpkgs with system
              home-manager.useUserPackages  = true;
              home-manager.backupFileExtension = "hm-bak";
              home-manager.extraSpecialArgs = { inherit inputs self; };
              home-manager.sharedModules    = [ sops-nix.homeManagerModules.sops ];
              home-manager.users = lib.genAttrs users (u: import ./home/${u});
            }
            {
              nixpkgs.config.allowUnfree = true;
              nixpkgs.overlays = [
                (final: _: {
                  unstable = import nixpkgs-unstable {
                    inherit (final.stdenv.hostPlatform) system;
                    config.allowUnfree = true;
                  };
                })
              ];
            }
          ] ++ extraModules;
        };
    in {
      nixosConfigurations.t14 = mkHost {
        hostname = "t14";
        users    = [ "patrikpersson" ];
        extraModules = [
          # No T14 Gen 4 Intel-specific module exists; compose generics.
          nixos-hardware.nixosModules.common-pc-laptop
          nixos-hardware.nixosModules.common-pc-ssd
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-gpu-intel
          lanzaboote.nixosModules.lanzaboote   # activated in modules/nixos/boot.nix
        ];
      };

      nixosConfigurations.server = mkHost {
        hostname = "server";
        users    = [];
      };

      devShells = forEachSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixVersions.stable nh nix-output-monitor
              sops age ssh-to-age sbctl
              statix deadnix nixpkgs-fmt
            ];
          };
        });

      formatter = forEachSystem (s: nixpkgs.legacyPackages.${s}.nixpkgs-fmt);
    };
}
```

**Server placeholder** (`hosts/server/default.nix`) — evaluates today, replaced when real hardware arrives:

```nix
{ lib, ... }: {
  imports = [ ./hardware-configuration.nix ];
  networking.hostName  = "server";
  system.stateVersion  = "25.11";
  boot.isContainer     = true;       # cheap eval-only stub; remove before nixos-install
}
```

**Shared-module pattern** — `modules/nixos/default.nix` aggregates everything both hosts get; each module is then gated by its own option (`my.desktop.enable`, `my.thinkpad.enable`, …) set in the per-host file. Example aggregation:

```nix
# modules/nixos/default.nix
{ ... }: { imports = [ ./common.nix ./users.nix ./desktop.nix ./thinkpad-t14-gen4.nix ]; }
```

```nix
# modules/nixos/common.nix
{ config, lib, pkgs, inputs, ... }: {
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store   = true;
    trusted-users         = [ "@wheel" ];
    substituters          = [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
    trusted-public-keys   = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nixpkgs.flake.source       = inputs.nixpkgs.outPath;

  time.timeZone      = lib.mkDefault "Europe/Stockholm";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap     = "us";
}
```

**Lockfile workflow.**

```bash
nix flake update                          # everything
nix flake update nixpkgs home-manager     # subset (Nix ≥ 2.19, positional)
nix flake metadata                        # inspect inputs
nix flake check                           # static eval all outputs
nixos-rebuild build --flake .#t14      # build without activating
nixos-rebuild build-vm --flake .#t14 && ./result/bin/run-t14-vm
sudo nixos-rebuild switch --flake .#t14
```

`inputs.X.nixpkgs.follows = "nixpkgs"` is mandatory on every input that itself depends on nixpkgs — otherwise the closure carries two nixpkgs trees and unnecessary rebuilds cascade. The **exception** is `hyprland` if you switch to its upstream flake: version-skew between mesa and wlroots manifests as FPS/lag bugs, so do **not** force `follows` there (<https://wiki.hypr.land/Nix/Hyprland-on-NixOS/>).

## 6. ThinkPad T14 Gen 4 Intel hardware module

A single annotated module collecting every laptop-specific knob. Drop in `modules/nixos/thinkpad-t14-gen4.nix`, gate with `my.thinkpad.enable = true;` from `hosts/t14/default.nix`.

```nix
{ config, lib, pkgs, ... }:
let cfg = config.my.thinkpad; in {
  options.my.thinkpad.enable = lib.mkEnableOption "T14 Gen 4 Intel tunables";

  config = lib.mkIf cfg.enable {
    # ---- Kernel & firmware -------------------------------------------------
    boot.kernelPackages = pkgs.linuxPackages_latest;
    # ↑ AX211 firmware reliability, libfprint protocol fixes, and Thunderbolt
    #   hotplug all benefit from the newest stable kernel rather than the LTS.
    hardware.enableRedistributableFirmware = true;
    hardware.cpu.intel.updateMicrocode     = true;
    boot.initrd.kernelModules = [ "i915" ];   # KMS for the LUKS prompt

    # ---- Graphics: Iris Xe + VA-API + oneVPL ------------------------------
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver         # iHD VA-API on Gen 11+
        vpl-gpu-rt                 # oneVPL runtime (replaced onevpl-intel-gpu)
        intel-compute-runtime      # OpenCL for ffmpeg/handbrake
      ];
    };
    environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
    boot.kernelParams = [ "i915.enable_guc=3" ];   # GuC+HuC firmware submission

    # ---- Suspend (s2idle only on Raptor Lake) ------------------------------
    # No knobs needed: kernel detects, /sys/power/mem_sleep = "[s2idle]".
    # Disable TrackPoint wake events if you observe spurious resumes:
    services.udev.extraRules = ''
      # Disable wake from the I²C ELAN TrackPoint controller
      ACTION=="add", SUBSYSTEM=="i2c", DRIVERS=="i2c_hid_acpi", \
        ATTR{power/wakeup}="disabled"
    '';

    # ---- Fan / thermal -----------------------------------------------------
    services.thermald.enable = true;             # Intel DPTF tables
    # thinkfan / throttled NOT needed on Gen 4 Intel.

    # ---- Power management --------------------------------------------------
    # Decision: power-profiles-daemon + thermald. PPD is what GNOME/KDE
    # natively talk to; it switches HWP EPP and platform_profile and is
    # mutually exclusive with TLP. TLP is the better choice if you want
    # charge-thresholds and granular USB autosuspend; see below.
    services.power-profiles-daemon.enable = true;
    # If you swap to TLP, do:
    #   services.power-profiles-daemon.enable = false;
    #   services.tlp.enable = true;
    #   services.tlp.settings = {
    #     CPU_DRIVER_OPMODE_ON_AC = "active"; CPU_DRIVER_OPMODE_ON_BAT = "active";
    #     CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
    #     CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
    #     START_CHARGE_THRESH_BAT0 = 75; STOP_CHARGE_THRESH_BAT0  = 80;
    #   };

    # ---- Fingerprint -------------------------------------------------------
    services.fprintd.enable = true;              # libfprint `synaptics` driver
    # Do NOT enable services.fprintd.tod (legacy Validity sensors).
    security.pam.services = {
      login.fprintAuth        = true;
      sudo.fprintAuth         = true;
      gdm-password.fprintAuth = true;
      # swaylock.fprintAuth   = true;   # if running Hyprland/Sway
    };

    # ---- Wi-Fi / Bluetooth -------------------------------------------------
    networking.networkmanager.enable          = true;
    networking.networkmanager.wifi.powersave  = false;
    # ↑ AX211 + s2idle occasionally fails to reassociate when powersave loops.
    hardware.bluetooth.enable      = true;
    hardware.bluetooth.powerOnBoot = true;
    services.blueman.enable        = true;

    # ---- Thunderbolt 4 / USB4 ---------------------------------------------
    services.hardware.bolt.enable = true;

    # ---- Audio (Realtek + SOF DSP) ----------------------------------------
    services.pulseaudio.enable = false;
    services.pipewire = {
      enable = true; alsa.enable = true; alsa.support32Bit = true;
      pulse.enable = true; wireplumber.enable = true;
    };
    services.pipewire.wireplumber.extraConfig."99-disable-suspend" = {
      "monitor.alsa.rules" = [{
        matches = [ { "node.name" = "~alsa_input.*"; }
                    { "node.name" = "~alsa_output.*"; } ];
        actions.update-props."session.suspend-timeout-seconds" = 0;
      }];
    };
    # ↑ Stops the 1 s relock pop on the Realtek codec.

    # ---- TrackPoint & touchpad --------------------------------------------
    services.libinput = {
      enable = true;
      touchpad = {
        tapping              = true;
        disableWhileTyping   = true;
        clickMethod          = "clickfinger";
        naturalScrolling     = true;
      };
    };
    hardware.trackpoint.enable      = true;
    hardware.trackpoint.sensitivity = 200;

    # ---- Brightness keys (needed for tiling WMs; harmless under GNOME/KDE) -
    environment.systemPackages = with pkgs; [ brightnessctl playerctl ];

    # ---- Firmware updates --------------------------------------------------
    services.fwupd.enable = true;
  };
}
```

Two things worth restating from this module: (a) **`power-profiles-daemon` is the default recommendation** on Raptor Lake U-series under GNOME or KDE because both desktops speak its D-Bus API natively and it cooperates with the kernel's `platform_profile`; switch to TLP **only** if you specifically want battery charge thresholds; never run both. (b) the WirePlumber suspend-timeout override is what eliminates the audio pop that almost everyone hits.

## 7. System decisions

**Bootloader: lanzaboote v1.0.x.** Lanzaboote v1.0.0 shipped on 10 December 2025 (<https://github.com/nix-community/lanzaboote/releases>) and is actively maintained. It signs a Unified Kernel Image (kernel + initrd + cmdline) with **your own keys** generated by `sbctl`, closing the systemd-boot gap where the initrd is unsigned and an attacker with brief physical access can drop a passphrase-exfiltrating one. A consulting laptop travelling to customer sites is a credible evil-maid target; the cost is one BIOS dance to enter Setup Mode and one extra `nixos-rebuild`. Install with `systemd-boot` first, switch after the first successful boot:

```nix
# modules/nixos/boot.nix
{ pkgs, lib, inputs, ... }: {
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];
  environment.systemPackages = [ pkgs.sbctl ];

  boot.loader.systemd-boot.enable      = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable    = true;
    pkiBundle = "/var/lib/sbctl";   # default since lanzaboote 0.4.x; older docs say /etc/secureboot
  };
}
```

Enrollment ritual: install with `systemd-boot`, rebuild once with the module imported but `enable = false`, `sudo sbctl create-keys`, reboot to firmware → Security → Reset to Setup Mode, boot back, `sudo sbctl enroll-keys --microsoft` (keep MS keys so future fwupd capsule updates keep working), set `enable = true`, rebuild, reboot, re-enable Secure Boot in firmware. Verify with `sbctl status` (expect `Secure Boot: enabled (user)`) and `bootctl status`. Reference: <https://github.com/nix-community/lanzaboote/blob/master/docs/getting-started/enable-secure-boot.md>, <https://wiki.nixos.org/wiki/Secure_Boot>.

**Disk encryption: GPT + 1 GiB ESP + LUKS2 (argon2id) + btrfs subvolumes.** Subvolumes `@ @home @nix @persist @snapshots @swap`. Mount options `noatime,compress=zstd:1,ssd,discard=async,space_cache=v2`. Btrfs over ext4 buys you O(1) CoW snapshots (you can roll back a botched switch from an initrd shell), transparent zstd compression that reclaims ~30–50% on `/nix`, and online resize / send-receive backups. The standard argument against — write amplification on heavy random-write databases — is irrelevant for a laptop. `@persist` is created on day one but **impermanence is not enabled yet**. The impermanence pattern (<https://github.com/nix-community/impermanence>) is excellent for forcing declarative discipline, but every new service silently loses state until you add its path to `environment.persistence` (`/var/lib/bluetooth`, `/var/lib/NetworkManager`, `/var/lib/fprintd`, `/etc/machine-id` …). Graduate to it after a month, with zero re-partitioning required.

**disko deferred.** Write the equivalent `disko.nix` (<https://github.com/nix-community/disko/blob/master/example/luks-btrfs-subvolumes.nix>), commit it, but do the first installation manually. Building the mental model of what disko automates is worth one evening; the killer use case is `nixos-anywhere` against the future server.

**Secrets: sops-nix.** For a single user today, sops-nix and agenix are roughly equivalent. The decisive factor is the server host on the horizon: SOPS keeps many secrets in one readable encrypted YAML, supports SOPS templates for rendering whole config files with secrets inline, and has a clean recipient-list workflow for adding a second host. agenix stays a sane choice for a hobby single-machine setup; we are optimising for the inevitable second host.

Generate the host age key from the SSH host key and the user age key from your personal SSH key:

```bash
# Host recipient (goes in .sops.yaml)
sudo cat /etc/ssh/ssh_host_ed25519_key.pub | nix run nixpkgs#ssh-to-age
# User recipient
mkdir -p ~/.config/sops/age
nix run nixpkgs#ssh-to-age -- -private-key -i ~/.ssh/id_ed25519 \
  -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

`.sops.yaml` at repo root (two-recipient pattern: user can edit, host can decrypt at activation):

```yaml
keys:
  - &user_patrikpersson  age10e9tt2qwq90y5hvl35dau0sm5cm4qvegtw2a70v7sz5fy99de42s9d5nkf
  - &host_t14   age1wnwfnrqhewjh39pmtyc8zhqw606znskt4h5p9s3pve4apd67gapqj6tr0k
  # - &host_server age1...    # filled in when server exists
creation_rules:
  - path_regex: secrets/laptop\.yaml$
    key_groups:
      - age: [ *user_patrikpersson, *host_t14 ]
  - path_regex: secrets/common\.yaml$
    key_groups:
      - age: [ *user_patrikpersson, *host_t14 ]   # add host_server when ready
```

**Wi-Fi PSK via sops-nix + NetworkManager** (`modules/nixos/wifi.nix`):

```nix
{ config, ... }: {
  sops.defaultSopsFile = ../../secrets/t14.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets."wifi/home_env" = {};         # appears at /run/secrets/wifi/home_env

  networking.networkmanager.enable = true;
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.secrets."wifi/home_env".path ];
    profiles.home = {
      connection    = { id = "home"; type = "wifi"; autoconnect = true; };
      wifi          = { mode = "infrastructure"; ssid = "$HOME_SSID"; };
      wifi-security = { key-mgmt = "wpa-psk"; psk = "$HOME_PSK"; };
      ipv4 = { method = "auto"; }; ipv6 = { method = "auto"; addr-gen-mode = "stable-privacy"; };
    };
  };
}
```

`secrets/t14.yaml` (edited via `sops secrets/t14.yaml`):

```yaml
wifi:
  home_env: |
    HOME_SSID=PerssonHome
    HOME_PSK=correct-horse-battery-staple
ssh:
  id_ed25519_patrikpersson: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAA...
    -----END OPENSSH PRIVATE KEY-----
```

**SSH private key via home-manager** (`home/patrikpersson/default.nix` excerpt):

```nix
{ config, ... }: {
  sops = {
    age.keyFile     = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/t14.yaml;
    secrets."ssh/id_ed25519_patrikpersson" = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      mode = "0600";
    };
  };
  programs.ssh.enable = true;
}
```

Two pitfalls: (a) never `builtins.readFile config.sops.secrets.X.path` — that re-introduces the plaintext into the world-readable Nix store; (b) if you regenerate `/etc/ssh/ssh_host_ed25519_key`, re-encrypt with `sops updatekeys secrets/t14.yaml` or the next boot fails activation (<https://github.com/Mic92/sops-nix>).

## 8. Desktop environment

Two options worth covering for this machine, plus a brief Sway mention. **Recommendation: GNOME 49 on Wayland**, with Hyprland as the alternative when you want to *learn the Wayland stack itself*.

**GNOME 49 (current on 25.11) — the recommended default.** Wayland-only as of 49 (the X11 session was removed; XWayland remains). Two lines do it:

```nix
{
  services.displayManager.gdm.enable    = true;
  services.desktopManager.gnome.enable  = true;
  programs.dconf.enable                 = true;
}
```

`services.xserver.*` paths are deprecated aliases in 25.11 — use the new `services.displayManager.*` / `services.desktopManager.*` namespace (<https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/services/desktop-managers/gnome.nix>). Power profile switching, brightness, screen lock, fractional scaling, fingerprint enrollment dialog, Pipewire screencast in OBS/Chromium/Firefox all work out of the box. Trade-off: Mutter is opinionated, extensions are an out-of-tree liability that occasionally break across rebuilds. GNOME is the right default for a *secondary learning machine that may handle real consulting work* — your time is better spent on the Nix layer than on bespoke compositor config.

**KDE Plasma 6** is the conservative alternative. Plasma 5 was removed in 25.11 (<https://blog.desdelinux.net/en/nixos-25-11-launch-news-gnome-49-rust/>); Plasma 6 is "the" KDE now. The wiki notes SDDM may be replaced with Plasma's own login manager on unstable (<https://wiki.nixos.org/wiki/KDE>), so pin to stable if you care:

```nix
{
  services.desktopManager.plasma6.enable        = true;
  services.displayManager.sddm.enable           = true;
  services.displayManager.sddm.wayland.enable   = true;
}
```

**Hyprland — the tiling option for power users.** Use the nixpkgs build, not the upstream flake, on a learning machine to avoid mesa/wlroots skew. Brightness binds are the well-known gotcha: the default config calls `brightnessctl` but the module does not install it (<https://github.com/NixOS/nixpkgs/issues/378681>). System side:

```nix
{
  programs.hyprland.enable           = true;
  programs.hyprland.xwayland.enable  = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.systemPackages = with pkgs; [
    kitty brightnessctl playerctl grim slurp wl-clipboard
    swaylock swayidle waybar wofi mako
  ];
  xdg.portal.enable       = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  security.polkit.enable  = true;
}
```

Home-manager side with sane T14 defaults (1920×1200 panel, 1.25× fractional scaling, libinput touchpad, XF86 keys):

```nix
{
  wayland.windowManager.hyprland = {
    enable = true; package = null; portalPackage = null;
    systemd.variables = [ "--all" ];
    settings = {
      "$mod"   = "SUPER";
      monitor  = ",preferred,auto,1.25";
      input.kb_layout = "us";
      input.touchpad = {
        natural_scroll = true; disable_while_typing = true;
        tap-to-click = true; clickfinger_behavior = true;
      };
      gestures.workspace_swipe = true;
      bindel = [
        ",XF86MonBrightnessUp,   exec, brightnessctl s 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl s 5%-"
        ",XF86AudioRaiseVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute,         exec, wpctl set-mute   @DEFAULT_AUDIO_SINK@ toggle"
      ];
      bind = [ "$mod, Q, exec, kitty" "$mod, L, exec, swaylock -f -c 000000" ];
      exec-once = [
        "swayidle -w timeout 300 'swaylock -f' timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on'"
        "waybar" "mako"
      ];
    };
  };
}
```

Sway, briefly: `programs.sway.enable = true;` + `wayland.windowManager.sway` in home-manager. More stable and mature than Hyprland, less flashy. The NixOS module already drops a `sway/config.d/nixos.conf` that wires the DBus activation environment, which is the critical step for portals to work.

## 9. Day-to-day workflow

**Rebuild tool: `nh`** (<https://github.com/nix-community/nh>, maintained by NotAShelf; originally by viperML). It is a Rust wrapper that unifies `nixos-rebuild`, `home-manager switch`, and garbage collection, with three features that change daily life: a closure **diff** via the `dix` crate (catches the unexpected GCC bump dragging in 300 MB of rebuilds), `nix-output-monitor` integration, and `nh clean` which removes GC roots left by `direnv` and stray `result/` symlinks that `nix-collect-garbage` ignores. Enable:

```nix
{
  programs.nh = {
    enable = true;
    flake  = "/etc/nixos";
    clean.enable    = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
  };
}
```

Daily commands: `nh os switch`, `nh os boot`, `nh os test`, `nh home switch`, `nh search firefox`, `nh clean all`. Keep `nixos-rebuild` around for the niche flags `nh` does not yet wrap (`--target-host`, `--use-substitutes`). Important: **do not enable both `programs.nh.clean.enable` and `nix.gc.automatic`** — the module asserts and refuses to build (<https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/programs/nh.nix>). Pick one; `nh clean` is preferable on a developer laptop because it cleans direnv roots.

**Flake input cadence.** Weekly `nix flake update` in the dev shell, build with `nh os switch`, read the diff, commit `flake.lock`. If a `nixpkgs` bump is broken (it happens on `nixos-unstable`), `git checkout flake.lock` reverts and tries again next week. Selective bumps:

```bash
nix flake update nixpkgs                      # modern (Nix ≥ 2.19)
nix flake update nixpkgs home-manager
nix flake lock --update-input nixpkgs         # legacy (still works)
```

**Generation cleanup and store optimisation** are handled by `nh clean all` (replaces `nix-collect-garbage --delete-older-than 14d` + cleaning the per-user profile + cleaning direnv roots). The system option `nix.settings.auto-optimise-store = true;` hardlinks identical store entries at build time.

**Rollback.** From the running system: `sudo nixos-rebuild switch --rollback`. From the bootloader: pick any older generation entry — every generation is a full boot target. Explicit selection: `sudo nix-env --list-generations -p /nix/var/nix/profiles/system`, then `sudo nix-env --switch-generation <N> -p /nix/var/nix/profiles/system && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch`.

**Channel / lock pinning.** Pin to `nixos-25.11` (stable) for the laptop. Use unstable through a `pkgs.unstable.*` overlay for one-off newer packages without dragging the whole system to unstable. Pin to a specific commit (`github:NixOS/nixpkgs/<sha>`) for client work that must reproduce months later. `follows` deduplicates transitive nixpkgs; force it on `home-manager`, `sops-nix`, `lanzaboote`; **don't** force it on `hyprland`'s upstream flake.

**direnv + nix-direnv per-project devShells.** This is what makes consulting work tractable.

```nix
# in home-manager
programs.direnv = {
  enable = true;
  nix-direnv.enable = true;
  config.global.hide_env_diff = true;
};
```

A project's `flake.nix`:

```nix
{
  inputs.nixpkgs.url     = "github:NixOS/nixpkgs/nixos-25.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ go_1_23 gopls golangci-lint postgresql_16 jq ];
          shellHook = ''echo "→ $(go version)"'';
        };
      });
}
```

Its `.envrc`:

```
use flake
dotenv_if_exists .env.local
watch_file flake.nix flake.lock
```

`direnv allow` once; `cd` into the project from now on activates the shell instantly (cached) and `cd` out deactivates it. `nix-direnv` installs a GC root so the shell survives `nh clean`. Every client gets their own pinned toolchain. Reference: <https://github.com/nix-community/nix-direnv>, <https://determinate.systems/blog/nix-direnv/>.

**Where to install what.** `environment.systemPackages` for tools needed before user activation or by every user (firmware utilities, browsers shared with multiple users); home-manager `home.packages` / `programs.<x>.enable` for everything else that lives in your `~`; `nix profile install` only for genuinely ad-hoc experiments — it is the un-declarative escape hatch. Rule of thumb: if it would belong in git, it belongs in home-manager.

## 10. Multi-tenant isolation architecture

Four levels, each fully expressible in the same flake, each strictly stronger than the previous. Pick the right level per context; do not over-engineer.

### Level 1 — Directory boundary (single UID)

Canonical pattern: one Linux user `patrikpersson`, per-client subtrees under `~/work/clients/<client>/`, each with its own `flake.nix` exposing a `devShell` and a `.envrc` of `use flake`. Secrets scoped by `.sops.yaml` path rules. SSH and browser partitioned by config.

```nix
# ~/work/clients/acme/flake.nix
{
  description = "Acme AB engagement shell";
  inputs.nixpkgs.url     = "github:NixOS/nixpkgs/nixos-25.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in {
        devShells.default = pkgs.mkShell {
          name = "acme-dev";
          packages = with pkgs; [
            terraform_1_9 awscli2 kubectl kubernetes-helm
            nodejs_20 pnpm postgresql_16 jq yq-go
          ];
          shellHook = ''
            export AWS_PROFILE=acme
            export KUBECONFIG=$PWD/.kube/config
            export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/acme.txt
            export GIT_AUTHOR_EMAIL="patrikcpatrikpersson@gmail.com"
            export GIT_COMMITTER_EMAIL="patrikcpatrikpersson@gmail.com"
          '';
        };
      });
}
```

`~/work/.sops.yaml` with per-client `creation_rules` (first match wins, evaluated relative to the `.sops.yaml`):

```yaml
keys:
  - &patrikpersson_admin    age1qprsxxx...patrikpersson...
  - &acme_recipient   age1acme0...acme-client-key...
  - &globex_recipient age1glbx0...globex-key...
  - &homelab_host     age1hmlb0...homelab-host-key...
creation_rules:
  - path_regex: clients/acme/.*\.(yaml|json|env|ini)$
    key_groups: [ { age: [ *patrikpersson_admin, *acme_recipient ] } ]
  - path_regex: clients/globex/.*\.(yaml|json|env|ini)$
    key_groups: [ { age: [ *patrikpersson_admin, *globex_recipient ] } ]
  - path_regex: homelab/.*\.(yaml|json|env|ini)$
    key_groups: [ { age: [ *patrikpersson_admin, *homelab_host ] } ]
  - path_regex: personal/.*\.(yaml|json|env|ini)$
    key_groups: [ { age: [ *patrikpersson_admin ] } ]
```

SSH routing via home-manager `programs.ssh.matchBlocks` with `identitiesOnly = true` on every block (critical — otherwise ssh-agent leaks every key to every host):

```nix
programs.ssh = {
  enable = true;
  matchBlocks = {
    "gitlab.acme.internal" = {
      user = "git"; identityFile = "~/.ssh/id_ed25519_acme"; identitiesOnly = true;
    };
    "git.globex.io" = {
      user = "git"; identityFile = "~/.ssh/id_ed25519_globex"; identitiesOnly = true;
    };
    "github.com" = {
      identityFile = "~/.ssh/id_ed25519_personal"; identitiesOnly = true;
    };
    "homelab.patrikpersson.tech *.lan" = {
      identityFile = "~/.ssh/id_ed25519_homelab"; forwardAgent = false;
    };
  };
};
```

Firefox profiles per client via `programs.firefox.profiles` — note the modern attribute name is `extensions.packages`, renamed from the flat `extensions` around home-manager 25.05:

```nix
programs.firefox = {
  enable = true;
  profiles = {
    personal = { id = 0; isDefault = true; name = "Personal"; };
    acme     = { id = 1; name = "ACME";
      settings."browser.startup.homepage" = "https://gitlab.acme.internal";
      settings."signon.rememberSignons"   = false; };
    globex   = { id = 2; name = "Globex"; };
    homelab  = { id = 3; name = "Homelab"; };
  };
};
```

Launch with `firefox -P Acme --no-remote`. **Trust boundary: none.** Same UID, same kernel, same FS, same Wayland clipboard, same DBus session. **What leaks:** essentially everything by default — ambient env, clipboard, ssh-agent (mitigated by `identitiesOnly`), browser state if you launch the wrong profile. **Overhead:** minimal — one user, one `home-manager` run. **Migration trigger:** an MSA with audit clauses, a daemon you want to scope to one client, or wanting a clean DM-level session switch.

### Level 2 — Account boundary (one Linux user per context)

Declare each user with `users.users.<name>` and a matching `home-manager.users.<name>` from the same flake.

```nix
# hosts/t14/users.nix
{ pkgs, ... }: {
  users.mutableUsers = false;
  users.groups.consulting = {};

  users.users.patrikpersson = {
    isNormalUser = true; uid = 1000;
    description = "Patrik Persson (personal)";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    shell = pkgs.zsh;
    hashedPasswordFile = "/run/secrets/patrikpersson-password";
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA...patrikpersson-yk" ];
  };
  users.users.acme = {
    isNormalUser = true; uid = 1101;
    extraGroups = [ "consulting" "networkmanager" ];
    shell = pkgs.zsh;
    hashedPasswordFile = "/run/secrets/acme-password";
  };
  users.users.globex = { /* uid 1102, similar */ };
  users.users.homelab = { /* uid 1200, no audio/video */ };

  systemd.tmpfiles.rules = [
    "d /home/patrikpersson 0700 patrikpersson users -"
    "d /home/acme    0700 acme    users -"
    "d /home/globex  0700 globex  users -"
    "d /home/homelab 0700 homelab users -"
  ];
}
```

The `home-manager.users.<name> = import ./home/<name>;` block in the flake (already shown in §5) attaches each user's HM config.

**Switching:** three options in increasing cleanliness.

1. Same graphical session, just a shell — cheap, leaks DBus/Wayland/clipboard:

   ```bash
   sudo machinectl shell acme@.host
   ```

   `machinectl shell` creates a fully isolated PAM/utmp/audit/keyring session, unlike `su`.

2. Run a single program as the other user under its own systemd scope:

   ```bash
   sudo systemd-run --machine=acme@.host --uid=1101 --pty --wait /run/current-system/sw/bin/zsh
   ```

3. Fresh graphical session — recommended for real client work. GDM "Switch User" or lock + login as the other account; this is the only path that gives you a separate Wayland compositor, separate clipboard, separate `XDG_RUNTIME_DIR`, separate ssh-agent and gnome-keyring. **Insist on Wayland** here (`services.displayManager.gdm.wayland = true;`) — X11 would defeat the isolation.

**Trust boundary:** UNIX DAC plus per-user systemd scope. **What leaks:** the kernel, all hardware, the network namespace, root if compromised. **Overhead:** moderate; N home-manager profiles to maintain, switching has real friction. **Migration trigger:** client wants services running independently with their own network identity; you want stop/start/destroy lifecycle.

### Level 3 — System boundary (NixOS containers via systemd-nspawn)

`containers.<name>` is a first-class NixOS module (`nixos/modules/virtualisation/nixos-containers.nix` in nixpkgs; <https://wiki.nixos.org/wiki/NixOS_Containers>). The container is a nested NixOS sharing the host kernel and `/nix/store` but isolated via PID/mount/UTS/IPC/network namespaces. **Declarative only for consulting work** — imperative `nixos-container create` produces snowflake state under `/var/lib/nixos-containers/` you cannot rebuild on a new laptop.

```nix
# modules/nixos/isolation/containers-acme.nix
{ config, lib, pkgs, ... }: {
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];
    externalInterface  = "wlp0s20f3";
  };

  containers.acme = {
    autoStart      = true;
    ephemeral      = false;            # keep /var, journal across reboots
    privateNetwork = true;
    hostAddress    = "10.233.1.1";
    localAddress   = "10.233.1.2";

    extraFlags = [
      "--drop-capability=CAP_SYS_MODULE"
      "--drop-capability=CAP_SYS_RAWIO"
    ];

    bindMounts = {
      "/data" = { hostPath = "/srv/clients/acme"; isReadOnly = false; };
      "/etc/age/acme.txt" = {
        hostPath = "/var/lib/containers-keys/acme.txt";
        isReadOnly = true;
      };
    };

    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "25.11";        # MUST be set per container

      networking = {
        firewall.allowedTCPPorts = [ 22 5432 ];
        useHostResolvConf = lib.mkForce false;
      };
      services.resolved.enable = true;

      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };

      users.users.dev = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA...patrikpersson-yk" ];
      };

      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_16;
        ensureDatabases = [ "acme" ];
        ensureUsers = [ { name = "acme"; ensureDBOptions.LOGIN = true; } ];
      };

      environment.systemPackages = with pkgs; [ git terraform_1_9 kubectl awscli2 sops age ];
    };
  };
}
```

Lifecycle: `nixos-container list / start / stop / login / root-login / run acme -- <cmd>`. For declarative containers, `nixos-rebuild switch` updates them in place; `systemctl restart container@acme` cycles a single one.

**Trust boundary:** Linux namespaces (PID, mount, UTS, IPC, net), cgroup v2, private veth pair, systemd-nspawn default capability set further restricted by `extraFlags`. **What leaks:** the kernel (shared, so kernel exploit = full break-out); the host `/nix/store` (so **never** store decrypted secrets through `pkgs.writeText`); whatever you `bindMount`. No GPU, no audio, no clipboard, no USB by default — excellent for compliance, but means you SSH from the host into the container for daily work. **Overhead:** higher; each container is its own openssh, its own user accounts, its own sops setup. **Migration trigger:** client signs a DPA referencing Art. 32 with explicit isolation language, or you have to execute untrusted code, or you need a different kernel/OS.

### Level 4 — Kernel boundary (microvm.nix / nixos-generators)

`microvm.nix` ([microvm-nix/microvm.nix](https://github.com/microvm-nix/microvm.nix); the canonical org migrated from `astro/microvm.nix`) declares a VM as just another `nixosConfiguration` and runs it as a systemd service. Default hypervisor qemu+KVM; alternatives cloud-hypervisor, firecracker, crosvm, kvmtool, stratovirt — only qemu+KVM has full virtiofs + 9p + control socket on a workstation. Pair with `nixos-generators` (<https://github.com/nix-community/nixos-generators>) when you need a portable disk image.

Add to top-level `flake.nix`:

```nix
inputs.microvm = {
  url = "github:microvm-nix/microvm.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Host module:

```nix
# modules/nixos/isolation/microvm-host.nix
{ inputs, ... }: {
  imports = [ inputs.microvm.nixosModules.host ];
  microvm.host.enable = true;
  microvm.autostart   = [ "acme-vm" ];
}
```

VM definition (another `nixosConfigurations` entry):

```nix
nixosConfigurations.acme-vm = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    inputs.microvm.nixosModules.microvm
    ({ config, pkgs, ... }: {
      networking.hostName = "acme-vm";
      system.stateVersion = "25.11";

      microvm = {
        hypervisor = "qemu";
        vcpu = 4;
        mem  = 4096;

        shares = [
          { proto = "virtiofs"; tag = "ro-store";
            source = "/nix/store"; mountPoint = "/nix/.ro-store"; }
          { proto = "virtiofs"; tag = "acme-data";
            source = "/srv/clients/acme"; mountPoint = "/data";
            socket = "acme-data.sock"; }
        ];

        volumes = [
          { image = "/var/lib/microvms/acme-vm/root.img";
            mountPoint = "/persist"; size = 20480; }
        ];

        interfaces  = [ { type = "tap"; id = "vm-acme"; mac = "02:00:00:01:01:01"; } ];
        forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
      };

      services.openssh.enable = true;
      users.users.dev = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA...patrikpersson-yk" ];
      };
    })
  ];
};
```

Lifecycle:

```bash
nix build .#nixosConfigurations.acme-vm.config.microvm.declaredRunner
sudo systemctl start  microvm@acme-vm
sudo systemctl status microvm@acme-vm
ssh -p 2222 dev@localhost
```

**Trust boundary:** separate Linux kernel, separate page tables, KVM-enforced isolation. Reduced to the qemu device-model attack surface and the KVM ioctl ABI. **What leaks:** virtiofs/9p shares you explicitly grant; the host `/nix/store` mounted read-only (binaries, not secrets); the routed network. Same-CPU side channels remain a concern, mitigated by Raptor Lake microcode + kernel mitigations. **Overhead:** high. Fixed RAM per VM (~512 MB default, shrinkable with `microvm-balloon`); separate kernel updates; no clipboard sharing; GUI requires Wayland forwarding (cloud-hypervisor experimental). **Justification gate** — only when one of: (a) signed DPA / regulatory requirement names VM-grade isolation (PCI-DSS scope, ISO 27001 Annex A.8 hardware/virtualisation controls); (b) you must execute untrusted code (third-party build chains, vendor SDKs, prospective M&A code review); (c) you need a non-NixOS workload (Windows installer, vendor appliance, Android emulator).

### Recommended default for Persson Tech AB

**Start at Level 1 for everything, with disciplined hygiene.** One user `patrikpersson`, per-client subdirs with their own `flake.nix` + `.envrc`, `identitiesOnly` SSH routing, per-client age recipients, separate Firefox profiles. This handles 2–3 clients comfortably as long as none of them is in a regulated industry.

**Escalate ONE client to Level 3** as soon as either of the following is true: a signed DPA mentions "appropriate technical measures" with explicit isolation language, or the client's data is regulated (health, financial, government, Art. 9 special categories). The container can live in your laptop flake today and copy to the homelab tomorrow as just another `containers.<name>` entry.

**Reserve Level 4** for: handling client-supplied binaries you cannot audit, building/testing systems for regulated industries, or one-off Windows/macOS tasks. Don't pay the RAM bill for normal consulting.

**Skip Level 2** unless you discover that the L1→L3 jump misses something specific (a fully separate desktop session for one client, no network or service isolation needed). L2's most useful real-world application here is separating the **homelab admin** identity from your daily user — root-level config errors in the homelab context are persistent and audit-visible, and a separate UID + journalctl scope makes incident review tractable.

Decision tree:

| Trigger | Action |
|---|---|
| New client signs a vanilla MSA, no audit clauses | Stay at L1 |
| Client requires an audit log of when their data was accessed | L1 → L2 (separate user, separate journal scope) |
| Client requires their tooling/services not share daemons with other clients | L2 → L3 |
| DPA references GDPR Art. 32 with explicit "separation of processing environments" | L3 minimum; consider L4 |
| You must run untrusted code (third-party CI runners, vendor SDKs, M&A code review) | L4 |
| You handle Art. 9 special-category data (health, biometric, union membership) | L4 + encrypted-at-rest volumes |

Numeric heuristic: if a client's annualised contract value is below the cost of one evening of L3 setup at your hourly rate, stay at L1; if it's above **and** they handle real personal data, do L3 from day one — migration cost grows with engagement age.

**GDPR Art. 32 — Sweden context.** Article 32 GDPR (<https://gdpr-info.eu/art-32-gdpr/>) requires the controller and processor to implement "appropriate technical and organisational measures" proportional to risk, considering "the state of the art, the costs of implementation … the nature, scope, context and purposes of processing as well as the risk … for the rights and freedoms of natural persons." The text is **risk-based and non-prescriptive** — it does not name systemd-nspawn, KVM, or any specific isolation primitive. As a processor under Art. 28 in Sweden, what binds you is the DPA (`personuppgiftsbiträdesavtal`) signed with each client controller; Art. 32 only requires you to *be able to demonstrate* what you chose and why, typically through a TOM register (`teknisk-organisatorisk åtgärdsregister`). IMY (Integritetsskyddsmyndigheten) enforces GDPR directly with no Swedish-specific addendum mandating VM isolation. **This is context, not legal advice** — get any DPA referencing personal data reviewed by a jurist.

## 11. Top 10 gotchas — T14 Gen 4 Intel + NixOS (last 12 months)

1. **s2idle is the only sleep state on Raptor Lake.** Symptom: BIOS exposes only Modern Standby; battery drains faster than legacy S3 on some workloads. Root cause: Intel removed S3 from Raptor Lake mobile silicon. Fix: nothing — confirm with `cat /sys/power/mem_sleep` (expect `[s2idle]`), keep the kernel on `linuxPackages_latest`. If TrackPoint or USB-C wakes the laptop spuriously, disable `power/wakeup` via the udev rule in §6. Sources: <https://julianyap.com/pages/2024-10-31-1730430246/>, <https://nobuto-m.github.io/post/2025/how-to-prevent-trackpoint-events-from-waking-up-thinkpad-t14-gen-5-amd-from-suspend/>.

2. **fwupd capsule update fails silently when Boot Order Lock is on.** Symptom: `fwupdmgr update` returns success but the next boot still reports the old BIOS, or you see `Not compatible with firmware version 0`. Root cause: Lenovo's "Boot Order Lock" blocks `fwupdx64.efi` from being registered as a one-shot boot entry. Fix: BIOS → Startup → disable Boot Order Lock, then `fwupdmgr refresh --force && fwupdmgr update`, then a **cold** reboot (full power-off, not `reboot`). Source: <https://bbs.archlinux.org/viewtopic.php?id=298467>, <https://github.com/fwupd/firmware-lenovo/issues/542>.

3. **Synaptics fingerprint enrollment hangs or reports protocol errors.** Symptom: `fprintd-enroll` reports `Device asked for more prints than we are providing` or stalls at `enroll-stage-passed`. Root cause: libfprint protocol drift versus a stale Synaptics Prometheus firmware, often combined with an LTS kernel missing USB quirks. Fix: `boot.kernelPackages = pkgs.linuxPackages_latest;`, run `fwupdmgr update` to refresh the fingerprint firmware, and **do not** set `services.fprintd.tod.enable` (that path is for older Validity 138a:00xx sensors). Sources: <https://bbs.archlinux.org/viewtopic.php?id=267692>, <https://discourse.nixos.org/t/fprintd-enroll-doesnt-add-fingerprint-no-error-message/35664>, <https://discourse.nixos.org/t/how-to-use-fingerprint-unlocking-how-to-set-up-fprintd-english/21901>.

4. **Fingerprint unlock stops working after resume.** Symptom: first enrollment succeeds; after `systemctl suspend`/resume the screen locker only accepts the password. Root cause: `fprintd.service` restarts on resume to re-init the USB device, but PAM sessions established at locker startup hold stale DBus connections. Fix: workaround in <https://github.com/NixOS/nixpkgs/issues/432276> restarts the screen-locker on resume via a systemd `sleep.target` hook; long-term fix lives in upstream `pam_fprintd`. For now, accept password fallback after suspend.

5. **Brightness keys do nothing under Hyprland.** Symptom: `wev` shows the keycode firing but the screen doesn't change. Root cause: `programs.hyprland.enable` generates a default config that calls `brightnessctl`, but the module does not install the binary. Fix: `environment.systemPackages = [ pkgs.brightnessctl ];`. Source: <https://github.com/NixOS/nixpkgs/issues/378681>.

6. **Audio pop after idle / wrong sink after suspend / headphone mute inverts.** Symptom: 0.5–1 s pop when audio first plays after a few seconds of silence; after resume audio routes to the wrong sink. Root cause: WirePlumber suspends ALSA nodes after 5 s and the Realtek codec needs ~1 s to relock the PLL. Fix: the `99-disable-suspend` snippet in §6, then `systemctl --user restart wireplumber`. Also ensure SOF firmware is present via `hardware.enableRedistributableFirmware = true;`. Sources: <https://discourse.nixos.org/t/prevent-pipewire-from-putting-audio-to-sleep/28505>, <https://github.com/NixOS/nixpkgs/issues/345313>.

7. **TrackPoint nub wakes the laptop from suspend.** Symptom: anything brushing the TrackPoint resumes the laptop in your bag. Root cause: ACPI wake bits left enabled on the I²C controller. Fix: udev rule in §6 disabling `power/wakeup` on the relevant `i2c_hid_acpi` device. Identify exact path with `cat /proc/acpi/wakeup` and `lsusb -t`. Pattern from <https://nobuto-m.github.io/post/2025/how-to-prevent-trackpoint-events-from-waking-up-thinkpad-t14-gen-5-amd-from-suspend/>.

8. **Thunderbolt 4 / USB4 dock loses USB or Ethernet after replug.** Symptom: after unplugging and replugging a TB4 dock, the dock's USB hub or Ethernet no longer enumerates; sometimes needs a reboot. Root cause: PCIe D3cold link-down delays not honoured on certain hotplug ports; combined with userspace authorization in `user` security mode. Fix: `services.hardware.bolt.enable = true;`, BIOS Thunderbolt security at `User`, kernel ≥ 6.12. One-off recovery: `echo 1 > /sys/bus/pci/devices/<id>/remove; echo 1 > /sys/bus/pci/rescan`. Sources: <https://bugs.launchpad.net/bugs/1991366>, <https://docs.kernel.org/admin-guide/thunderbolt.html>.

9. **VAAPI / hardware video decode falls back to software.** Symptom: `vainfo` shows the iHD profile but Firefox/mpv/OBS still software-decode; `intel_gpu_top` shows 0% on the video engine. Root cause: two missing pieces on NixOS — `intel-media-driver` for iHD, `vpl-gpu-rt` (renamed from `onevpl-intel-gpu` in 24.05) for oneVPL/QSV — and the `LIBVA_DRIVER_NAME=iHD` env var. Fix: the `hardware.graphics` block in §6, plus `media.ffmpeg.vaapi.enabled=true` in Firefox `about:config`. Verify with `nix shell nixpkgs#libva-utils -c vainfo`. Sources: <https://wiki.nixos.org/wiki/Intel_Graphics>, <https://wiki.nixos.org/wiki/Accelerated_Video_Playback>.

10. **Intel AX211 Wi-Fi not detected at boot or drops on resume.** Symptom: dmesg shows `iwlwifi … direct firmware load for iwlwifi-so-a0-gf-a0-XX.ucode failed`, or NetworkManager hangs on resume. Root cause: missing redistributable firmware bundle and/or AX211 firmware bugs in older `linux-firmware`. Fix: `hardware.enableRedistributableFirmware = true;`, `boot.kernelPackages = pkgs.linuxPackages_latest;`, `networking.networkmanager.wifi.powersave = false;`. Sources: <https://discourse.nixos.org/t/how-to-use-latest-iwlwifi-firmware-from-linux-firmware/15395>, <https://discourse.nixos.org/t/non-free-firmware-not-loaded-after-update/52183>.

Bonus context: the `T14s won't power down` thread (<https://discourse.nixos.org/t/thinkpad-t14s-wont-power-down/46809>) fixed via nixos-hardware PR #1027 is on the T14s chassis, not the T14 — keep an eye on it if you also encounter shutdown-hang symptoms.

## 12. Further reading

**Manuals**
- NixOS manual (stable): <https://nixos.org/manual/nixos/stable/>
- nix.dev tutorials: <https://nix.dev/>
- home-manager manual: <https://nix-community.github.io/home-manager/>
- NixOS 25.11 release notes: <https://nixos.org/blog/announcements/2025/nixos-2511/>

**Hardware**
- nixos-hardware repo + module index: <https://github.com/NixOS/nixos-hardware>
- ArchWiki T14/T14s Intel Gen 4: <https://wiki.archlinux.org/title/Lenovo_ThinkPad_T14/T14s_(Intel)_Gen_4>
- Field report for this exact model: <https://julianyap.com/pages/2024-10-31-1730430246/>
- fwupd LVFS device index: <https://fwupd.org/lvfs/devices/>
- Lenovo T14 Gen 4 / P14s Gen 4 HMM (mirror): <https://manuals.plus/m/9e6da2b6f4280b18e8d2674b425c98a3c73b1135e5fc1d7b49c20f9203ff8c88>

**Flakes and reference configs**
- Misterio77 starter configs: <https://github.com/Misterio77/nix-starter-configs>
- Mic92 dotfiles (flake-parts exemplar): <https://github.com/Mic92/dotfiles>
- hlissner dotfiles (vanilla flakes, profiles pattern): <https://github.com/hlissner/dotfiles>
- flake-parts: <https://flake.parts/>

**Secrets, boot, disks**
- sops-nix: <https://github.com/Mic92/sops-nix>
- agenix: <https://github.com/ryantm/agenix>
- lanzaboote: <https://github.com/nix-community/lanzaboote>
- disko: <https://github.com/nix-community/disko>
- impermanence: <https://github.com/nix-community/impermanence>

**Isolation**
- NixOS containers wiki: <https://wiki.nixos.org/wiki/NixOS_Containers>
- microvm.nix: <https://github.com/microvm-nix/microvm.nix> and handbook <https://microvm-nix.github.io/microvm.nix/>
- nixos-generators: <https://github.com/nix-community/nixos-generators>
