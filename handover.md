# NixOS T14 — handover

Consumed by the next Claude Code session. Skim §1 + §6 first, then start.

## 1. Status

Working install of NixOS 25.11 on a ThinkPad T14 Gen 4 Intel. LUKS2 +
btrfs subvolumes, GNOME 49 on Wayland under GDM, PipeWire, fprintd
wired, fwupd, Thunderbolt 4 via boltd, Firefox, claude-code. Git +
gh installed and authed; user pushes directly from the laptop.

Edit-validate-iterate happens on a macOS peer (`~/Code/nixos-config`)
where `nix flake check` runs in ~10s before push. Builds happen on
the T14 because that's where the substituter cache hits and where
the system is. Either machine can push; both pull the same `main`.

No staging environment, no branches, no PRs — single `main`, one
commit per logical change, push-and-pull as the sync mechanism.

## 2. Repo layout

```
nixos-config/
├── flake.nix                       # nixpkgs 25.11 + nixos-hardware master
├── flake.lock                      # tracked
├── hosts/
│   └── t14/
│       ├── default.nix             # system-wide config for this host
│       └── hardware-configuration.nix  # generated; real UUIDs; tracked
├── modules/
│   └── nixos/
│       ├── thinkpad-t14-gen4.nix   # chassis-specific tunables
│       └── desktop-gnome.nix       # GDM + GNOME 49 + dconf + fonts
└── handover.md                     # this file
```

`hosts/t14/default.nix` imports `hardware-configuration.nix` plus the two
shared modules. The flake passes nixos-hardware's `common-pc-laptop`,
`common-pc-ssd`, `common-cpu-intel`, `common-gpu-intel` alongside the
host module — there is **no** Gen 4 Intel profile upstream as of
2026-05; composing from generics is the right answer.

## 3. Cross-machine workflow

**Edit cycle (Mac is faster for iteration, T14 also works):**

```bash
# wherever you edit:
cd ~/Code/nixos-config   # or /etc/nixos on T14
$EDITOR <file>
nix flake check                 # ~10s, eval-only; catches syntax + option errors
git add -A
git commit -m "..."
git push
```

**Rebuild (always on T14):**

```bash
cd /etc/nixos
sudo git pull --rebase origin main
sudo nixos-rebuild dry-build --flake /etc/nixos#t14   # optional, ~30s
sudo nixos-rebuild switch --flake /etc/nixos#t14
```

`nix` lives at `/nix/var/nix/profiles/default/bin/nix` on the Mac;
the nushell PATH in `~/dotfiles/base/nushell/env.nu` already prepends
it. Experimental features (`nix-command flakes`) are set in
`~/.config/nix/nix.conf` on the Mac and in the system `nix.settings`
on the T14.

If `git pull --rebase` reports a `flake.lock` conflict (both peers
ran `nix flake lock` independently), the resolution is "take whichever
side; they're both valid pins": `git checkout --ours flake.lock`
during the rebase, then `git rebase --continue`.

## 4. Done — already absorbed (with gotchas worth remembering)

- Flakes + nix-command globally (`nix.settings.experimental-features`).
- Unfree allowed (`nixpkgs.config.allowUnfree = true`) — gates
  claude-code. Tighten to `allowUnfreePredicate` if/when an explicit
  allowlist is wanted.
- System packages: `git gh vim tree file curl wget htop pciutils
  usbutils claude-code`. Anything user-scoped is deliberately not
  here — wait for home-manager (§6 step 1).
- Chassis module covers: i915-in-initrd, GuC/HuC submission, VAAPI
  (intel-media-driver + vpl-gpu-rt + intel-compute-runtime,
  `LIBVA_DRIVER_NAME=iHD`), TrackPoint-wake suppression via udev,
  thermald, **power-profiles-daemon with `services.tlp.enable =
  mkForce false`** (nixos-hardware's common-pc-laptop enables TLP by
  default; PPD and TLP are mutually exclusive — PPD wins because
  GNOME talks to it natively), Synaptics fprintd with PAM glued in
  (`mkForce true` because something upstream defaults the same options
  to `false`; investigate later if curious), AX211 powersave off,
  Bluetooth + blueman, boltd for TB4, PipeWire/WirePlumber with the
  ALSA suspend-timeout set to 0 (kills the Realtek post-idle pop),
  libinput + TrackPoint sensitivity, brightnessctl + playerctl on
  PATH, fwupd.
- GNOME 49 module covers: GDM + desktopManager.gnome + dconf +
  `services.xserver.xkb.layout = "us"` + Noto/Liberation fonts.
  **Gotcha**: `noto-fonts-emoji` was renamed to
  `noto-fonts-color-emoji` in nixpkgs — eval errors point at it
  immediately if you copy old guides.
- Firefox via `programs.firefox.enable`. The reason it's installed
  and not just GNOME Web (Epiphany): Cloudflare's bot detection 403s
  Epiphany's WebKitGTK fingerprint on claude.ai, github.com sometimes,
  etc. Firefox sails through. Worth knowing if a friend asks "why
  doesn't Epiphany work on $site."

## 5. Verifications uncollected

Do these once before changing anything — they confirm the modules
that landed actually wired the hardware. None require code changes.

- `sudo fprintd-enroll patrikpersson` — confirms libfprint synaptics
  driver path. Should walk you through 5 prints.
- Settings → Power → three profiles (Power Saver / Balanced /
  Performance) — confirms PPD is wired, TLP is properly off.
- `fwupdmgr get-devices` — should list BIOS, fingerprint sensor,
  Thunderbolt controller, SSD.
- `boltctl list` — empty without a dock, non-empty when one's plugged.
- Lid-close in a bag (TrackPoint brush) → confirm the machine stays
  asleep. The udev rule disabling `power/wakeup` on `i2c_hid_acpi`
  should handle it.

If any of these fail, the chassis module
(`modules/nixos/thinkpad-t14-gen4.nix`) is the place to fix.

## 6. Roadmap — pick up here

In order. Each is one commit, one rebuild.

### Step 1 — home-manager as a NixOS module

The biggest QoL win remaining. Adding it lets the user's identity
(`git`, `~/.ssh/config`, shell aliases, GNOME dconf settings, Firefox
profiles) live in the flake. Without it the user keeps running
imperative `git config --global ...` on every fresh machine.

Design decisions to inherit (don't re-litigate):

- home-manager as a **NixOS module**, not standalone. One
  `nixos-rebuild switch` rebuilds system + user atomically, rolls
  back together, and HM modules can read `osConfig`.
- `home-manager.useGlobalPkgs = true` and `useUserPackages = true`
  so HM shares the system nixpkgs (no duplicate closure).
- `home-manager.backupFileExtension = "hm-bak"` so the first switch
  doesn't error when HM finds existing dotfiles in `~`.
- Add to flake inputs:
  `home-manager.url = "github:nix-community/home-manager/release-25.11"`
  with `inputs.nixpkgs.follows = "nixpkgs"`.
- Directory: `home/patrikpersson/default.nix` for the user's HM
  config; sharable bits as `modules/home-manager/<topic>.nix`.

Suggested first content for `home/patrikpersson/default.nix`:
`programs.git` (user.name, user.email = patrikcpersson@gmail.com,
init.defaultBranch = main, pull.rebase = true), `programs.ssh`
(empty for now, matchBlocks land with step 2 once SSH keys exist),
`programs.firefox.profiles` (one default profile), a `home.packages`
list to migrate things the user wants in `$HOME` (ripgrep, fd, bat,
eza, jq, etc.), `home.stateVersion = "25.11"`.

### Step 2 — sops-nix

Resolves "Wi-Fi PSK and SSH keys are imperative." Both move to
encrypted YAML decrypted by the host's age key at activation.

Design decisions to inherit:

- Recipients in `.sops.yaml`: one user age key (derived from a
  personal SSH ed25519 via `ssh-to-age`), one host age key (derived
  from `/etc/ssh/ssh_host_ed25519_key.pub` via `ssh-to-age`).
- Per-host secrets file: `secrets/t14.yaml`.
- First secret to migrate: a freshly-generated SSH ed25519 for the
  user, deployed via `sops.secrets."ssh/id_ed25519_persson".path`
  → `~/.ssh/id_ed25519` with mode `0600`.
- Wi-Fi via `networking.networkmanager.ensureProfiles` reading
  `environmentFiles` from sops-managed paths (the standard sops-nix
  pattern — works because NM is the only consumer).

Add to flake inputs:
`sops-nix.url = "github:Mic92/sops-nix"`, `inputs.nixpkgs.follows
= "nixpkgs"`. Module: `sops-nix.nixosModules.sops`; for HM use
`sops-nix.homeManagerModules.sops` from inside the HM block.

Pitfall to remember: never `builtins.readFile config.sops.secrets.X.path`
— that lands the decrypted plaintext in `/nix/store`, which is
world-readable. Always reference paths, never contents.

### Step 3 — Lanzaboote (Secure Boot with own keys)

Anti-evil-maid for a consulting laptop. Two phases.

Phase A — enroll keys (one-off BIOS dance):

```bash
sudo sbctl create-keys
sudo bootctl status            # confirm systemd-boot still active
sudo reboot                    # BIOS → Security → Reset to Setup Mode
# back at the DE:
sudo sbctl enroll-keys --microsoft   # keep MS keys so fwupd capsule updates still work
```

Phase B — flip the bootloader in the flake:

```nix
imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];
boot.loader.systemd-boot.enable = lib.mkForce false;
boot.lanzaboote = {
  enable = true;
  pkiBundle = "/var/lib/sbctl";    # default since lanzaboote 0.4.x
};
environment.systemPackages = [ pkgs.sbctl ];
```

Rebuild, reboot, enter BIOS, re-enable Secure Boot. Verify with
`sbctl status` (expect "Secure Boot: enabled (user)").

Add to flake inputs: `lanzaboote.url = "github:nix-community/lanzaboote/v1.0.0"`
with `inputs.nixpkgs.follows = "nixpkgs"`.

### Step 4 — `nh` and direnv + nix-direnv

QoL, not load-bearing. `nh` is a Rust wrapper that adds closure
diffs and nix-output-monitor to rebuilds; `nix-direnv` makes
per-project devShells transparent. Both are uncontroversial.

```nix
programs.nh = {
  enable = true;
  flake = "/home/patrikpersson/nixos-config";   # symlink /etc/nixos here
  clean.enable = true;
  clean.extraArgs = "--keep-since 7d --keep 5";
};
```

**Asserts** if `nix.gc.automatic = true` is also set — pick one.
`nh clean` wins because it also cleans direnv GC roots.

home-manager side:

```nix
programs.direnv = {
  enable = true;
  nix-direnv.enable = true;
  config.global.hide_env_diff = true;
};
```

### Step 5 — Multi-tenant isolation

Deferred. Pull it forward only when a real client engagement has a
DPA clause that names isolation. Until then, single user, no
containers, no microvms — premature for a daily-driver laptop.

## 7. Explicitly out of scope

- **Telia Wi-Fi PSK rotation.** Skipped per user decision. Don't
  bring it up.
- **GitHub repo visibility flip back to private.** Skipped per user
  decision. Stay on public until further notice.
- **A second host (server, VPS, homelab).** No physical/virtual
  machine to target yet. The flake structure (`hosts/<name>`) is
  already shaped so adding one is a 5-line change in `flake.nix` +
  a `hosts/<name>/` directory.

## 8. First-session checklist

Before changing anything, the next agent should run these and read
the answers — they catch state drift if the user did something
imperatively between sessions:

```bash
cd /etc/nixos
git status                     # working tree clean? on main?
git log --oneline -10          # any imperative commits since this handover?
nixos-version                  # confirm still 25.11
findmnt -t btrfs               # all 6 subvolumes still mounted?
systemctl --failed             # any failed services?
fwupdmgr get-devices | head -40  # firmware sanity
boltctl domains                # bolt daemon up
```

If all green, start step 1 (home-manager). Cite this handover when
referencing past decisions; don't re-derive them.
