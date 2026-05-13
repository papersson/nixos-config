# NixOS T14 — handover

Consumed by the next Claude Code session. Skim §1 + §6 first, then start.

## 1. Status

Working install of NixOS 25.11 on a ThinkPad T14 Gen 4 Intel. LUKS2 +
btrfs subvolumes, GNOME 49 on Wayland under GDM, PipeWire, fprintd
wired, fwupd, Thunderbolt 4 via boltd, Firefox. Git + gh installed
and authed; user pushes directly from the laptop.

**home-manager is now the user-config layer** (wired as a NixOS module).
Login shell is zsh; prompt is starship; jumps via zoxide; history via
atuin; cross-tool completion via carapace. Terminal is Ghostty.
claude-code comes from `pkgs.unstable.*` (a `nixpkgs-unstable` overlay
in the flake), so it tracks closer to npm than the 25.11 channel does.

Edit-validate-iterate happens on a macOS peer (`~/Code/nixos-config`)
where `nix flake check` runs in ~10s before push. Builds happen on
the T14 because that's where the substituter cache hits and where
the system is. Either machine can push; both pull the same `main`.

No staging environment, no branches, no PRs — single `main`, one
commit per logical change, push-and-pull as the sync mechanism.

## 2. Repo layout

```
nixos-config/
├── flake.nix                       # nixpkgs 25.11 + nixpkgs-unstable + home-manager + nixos-hardware
├── flake.lock                      # tracked
├── CLAUDE.md                       # project-level Claude instructions for this repo
├── hosts/
│   └── t14/
│       ├── default.nix             # system-wide config for this host
│       └── hardware-configuration.nix  # generated; real UUIDs; tracked
├── modules/
│   └── nixos/
│       ├── thinkpad-t14-gen4.nix   # chassis-specific tunables
│       └── desktop-gnome.nix       # GDM + GNOME 49 + dconf + fonts
├── home/
│   └── patrikpersson/
│       ├── default.nix             # home-manager user config (git, ghostty, zsh, starship, zoxide, atuin, carapace, claude home.file refs)
│       ├── starship.toml           # consumed via builtins.fromTOML + readFile
│       └── claude/
│           ├── CLAUDE.md           # deployed to ~/.claude/CLAUDE.md by HM
│           └── statusline.sh       # deployed to ~/.claude/statusline.sh (executable)
├── docs/
│   └── drafts/
│       └── config-architecture.md  # open question: dotfiles ↔ Nix integration; CLAUDE.md per-host split
├── reference.md                    # untracked — comprehensive setup guide and gotcha catalogue
└── handover.md                     # this file
```

`hosts/t14/default.nix` imports `hardware-configuration.nix` plus the two
chassis modules. The flake passes nixos-hardware's `common-pc-laptop`,
`common-pc-ssd`, `common-cpu-intel`, `common-gpu-intel` alongside the
host module — there is **no** Gen 4 Intel profile upstream as of
2026-05; composing from generics is the right answer.

## 3. Cross-machine workflow

**Edit cycle (Mac is faster for iteration, T14 also works):**

```bash
# wherever you edit:
cd ~/Code/nixos-config   # or /etc/nixos on T14
$EDITOR <file>
git add path/to/new-or-changed.nix   # required — flake evaluator only sees git-tracked files
nix flake check                       # ~10s, eval-only; catches syntax + option errors
git commit -m "..."
git push
```

**Rebuild (always on T14):**

```bash
cd /etc/nixos
git pull --rebase origin main         # /etc/nixos is user-writable now (tmpfiles rule)
sudo nixos-rebuild dry-build --flake /etc/nixos#t14   # optional, ~30s
sudo nixos-rebuild switch --flake /etc/nixos#t14
```

If `git pull --rebase` reports a `flake.lock` conflict (both peers
ran `nix flake lock` independently), the resolution is "take whichever
side; they're both valid pins": `git checkout --ours flake.lock`
during the rebase, then `git rebase --continue`.

## 4. Done — already absorbed

**System bringup (earlier sessions):**

- Flakes + nix-command globally (`nix.settings.experimental-features`).
- Unfree allowed (`nixpkgs.config.allowUnfree = true`).
- Chassis module covers: i915-in-initrd, GuC/HuC submission, VAAPI
  stack, TrackPoint-wake suppression via udev, thermald,
  **power-profiles-daemon with `services.tlp.enable = mkForce false`**
  (nixos-hardware's common-pc-laptop enables TLP by default; PPD and
  TLP are mutually exclusive — PPD wins because GNOME talks to it
  natively), Synaptics fprintd with PAM glued in, AX211 powersave off,
  Bluetooth + blueman, boltd for TB4, PipeWire/WirePlumber with the
  ALSA suspend-timeout set to 0, libinput + TrackPoint sensitivity,
  brightnessctl + playerctl, fwupd.
- GNOME 49 module: GDM + desktopManager.gnome + dconf + Noto/Liberation
  fonts. `noto-fonts-emoji` is renamed to `noto-fonts-color-emoji` in
  nixpkgs — eval errors there immediately if you copy old guides.
- Firefox via `programs.firefox.enable`. Reason it's installed and not
  just GNOME Web (Epiphany): Cloudflare 403s Epiphany's WebKitGTK
  fingerprint on claude.ai etc.

**This session's work (commits `e5135d1`, `fc33fee`, `5f8401a`):**

- **home-manager 25.11 as a NixOS module** (commit `e5135d1`).
  `useGlobalPkgs`, `useUserPackages`, `backupFileExtension = "hm-bak"`.
  User config at `home/patrikpersson/default.nix`. **Gotcha**: HM 25.11
  renamed `programs.git.userName`/`userEmail`/`extraConfig` into a flat
  `programs.git.settings` attrset; old guides will eval-warn until
  fixed. HM writes git config to `~/.config/git/config` (XDG path),
  not `~/.gitconfig`.
- **`/etc/nixos` made user-writable** via `systemd.tmpfiles.rules` so
  edits don't need sudo; rebuilds still do.
- **Ghostty terminal** (`programs.ghostty` HM module) with translated
  dotfiles config, Catppuccin Mocha theme active, JetBrainsMono Nerd
  Font installed.
- **claude-code switched to `pkgs.unstable.claude-code`** via a new
  `nixpkgs-unstable` flake input + overlay. Stable's 25.11 claude-code
  is days–weeks behind npm. Bump via `nix flake update nixpkgs-unstable`.
  Pattern is reusable for any fast-moving package (`pkgs.unstable.X`).
- **Claude Code config deployed via HM**: `~/.claude/CLAUDE.md` and
  `~/.claude/statusline.sh` are HM-managed symlinks; `settings.json`
  is **deliberately not** managed by HM because claude-code writes
  back to it — it lives directly on disk. **Gotcha**: the original
  statusline shebang `#!/bin/bash` doesn't work on NixOS (no `/bin/bash`);
  fixed to `#!/usr/bin/env bash` for portability with macOS.
- **Zsh stack** (`programs.zsh` + `programs.starship` + `programs.zoxide`
  + `programs.atuin` + `programs.carapace`). Vi keymap default, prefix-
  search keybinds, history aliases (`ls=eza`, `g=git`, etc.). Atuin
  owns `Ctrl-R`; up-arrow keeps prefix-search (atuin's takeover
  disabled via `--disable-up-arrow`). Carapace bridges fall back to
  zsh/fish/bash/inshellisense via `CARAPACE_BRIDGES` env var.
- **Login shell set to zsh** at the NixOS level. Takes effect on next
  GNOME login (not on rebuild).
- **Project-level `/etc/nixos/CLAUDE.md`** documenting repo layout,
  workflow gotchas, conventions.
- **Global `~/.claude/CLAUDE.md` rewritten** from inherited macOS
  content into a tight NixOS-aware version (~50 lines vs ~210 before).
  Source is `home/patrikpersson/claude/CLAUDE.md` in this repo.
- **Architecture draft at `docs/drafts/config-architecture.md`** —
  open decision: how to integrate `~/dotfiles` with Nix. Recommends
  Option B (dotfiles as flake input) as next step, with eventual
  Option A (nix-darwin + one repo). Captures the CLAUDE.md per-host
  split plan.

## 5. Verifications uncollected

Once before changing anything, confirm the modules wired the hardware
and the tooling stack actually works.

Hardware (from earlier sessions, still uncollected):

- `sudo fprintd-enroll patrikpersson` — confirms libfprint synaptics
  driver path. Should walk you through 5 prints.
- Settings → Power → three profiles (Power Saver / Balanced /
  Performance) — confirms PPD is wired, TLP is properly off.
- `fwupdmgr get-devices` — should list BIOS, fingerprint sensor,
  Thunderbolt controller, SSD.
- `boltctl list` — empty without a dock, non-empty when one's plugged.
- Lid-close in a bag (TrackPoint brush) → confirm the machine stays
  asleep.

Tooling (new since last handover):

- In a fresh Ghostty: shell is zsh, prompt is starship, `Ctrl-R` opens
  atuin's fuzzy picker, Tab on `gh pr `/`kubectl ` shows carapace
  completions.
- `claude --version` ≥ 2.1.137 (from `pkgs.unstable.*`).
- `cat ~/.claude/CLAUDE.md` shows the new NixOS-aware content (not
  the old macOS dotfiles content).

If any hardware verification fails, the chassis module
(`modules/nixos/thinkpad-t14-gen4.nix`) is the place to fix. If any
tooling fails, check `home/patrikpersson/default.nix` and confirm
the user logged out + back in after the shell change.

## 6. Roadmap — pick up here

In order. Each is one commit, one rebuild.

### Step 1 — home-manager as a NixOS module ✓ DONE

Landed in commit `e5135d1`. See §4 for details and gotchas captured.

### Step 2 — sops-nix (NEXT)

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
`sops-nix.homeManagerModules.sops` from inside the HM block (it's
declared via `home-manager.sharedModules` at the flake level).

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

### Step 5 — Dotfiles ↔ Nix integration (Option B)

Reading: `docs/drafts/config-architecture.md`.

Current state has `~/dotfiles/` and `/etc/nixos/` both holding text
files (CLAUDE.md, statusline.sh, starship.toml). The fix:

- Add `~/dotfiles` as a flake input with `flake = false`
- Point `home.file."x".source` at `${inputs.dotfiles}/path` instead
  of `./local/copy`
- Delete the in-repo copies under `home/patrikpersson/claude/`
- macOS-side workflow stays unchanged (its `install.sh` already
  consumes the same files)

Prereqs:
- Push `~/dotfiles` to GitHub if not already there (currently has
  a remote — verify).
- Decide on iteration loop: every edit to dotfiles → push →
  `nix flake update dotfiles` → rebuild. Or use `git+file://` for
  local iteration and `--impure` / `--no-write-lock-file`.

This is also when to do the per-host CLAUDE.md split documented in
the architecture draft: split current `home/patrikpersson/claude/CLAUDE.md`
into `base/claude/CLAUDE.md` (universal) + `hosts/t14/claude/CLAUDE.md`
(NixOS-specific), and concatenate via `builtins.readFile`.

### Step 6 — Multi-tenant isolation

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
- **macOS via nix-darwin.** Option A in the architecture draft —
  destination, not next step. Revisit after step 5.

## 8. First-session checklist

Before changing anything, run these and read the answers — they
catch state drift if the user did something imperatively between
sessions:

```bash
cd /etc/nixos
git status                     # working tree clean? on main? reference.md untracked is normal
git log --oneline -10          # any imperative commits since this handover?
nixos-version                  # confirm still 25.11
findmnt -t btrfs               # all 6 subvolumes still mounted?
systemctl --failed             # any failed services?
fwupdmgr get-devices | head -40  # firmware sanity
boltctl domains                # bolt daemon up
echo $SHELL                    # /run/current-system/sw/bin/zsh — confirms login shell change took
claude --version               # ≥ 2.1.137 confirms pkgs.unstable overlay landed
```

If all green, start step 2 (sops-nix). Cite this handover when
referencing past decisions; don't re-derive them.
