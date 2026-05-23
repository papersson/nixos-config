# CLAUDE.md — NixOS config repo

Flake configuring two hosts for a single user (`patrikpersson`): the `t14` ThinkPad laptop and the `z840` headless homelab server. NixOS 25.11 on both.

## Layout

- `flake.nix` — inputs (nixpkgs 25.11, nixpkgs-unstable, home-manager release-25.11, nixos-hardware, sops-nix, lanzaboote, nixvim, matugen, zen-browser) and the `nixosConfigurations.{t14,z840}` outputs
- `flake.lock` — pinned input revisions; commit alongside `flake.nix`
- `hosts/t14/` — laptop host config + auto-generated `hardware-configuration.nix`
- `hosts/z840/` — server host config + auto-generated `hardware-configuration.nix`
- `modules/nixos/` — reusable system modules (T14 hardware tunables, Hyprland desktop + greetd, declarative Wi-Fi via sops). Currently t14-only; z840 imports its bits directly from `hosts/z840/default.nix`.
- `home/patrikpersson/` — home-manager user config and bundled assets. Two entry points:
  - `default.nix` — t14 (desktop: imports Hyprland, theming, desktop-shell, zen-browser, ghostty, sops)
  - `server.nix` — z840 (headless: nvim + CLI tooling + claude-code only)
- `home/patrikpersson/claude/` — Claude Code global `~/.claude/CLAUDE.md` source. Split into `CLAUDE.common.md` (universal rules, shared across hosts) and per-host `CLAUDE.<host>.md` (Environment section). Each host config concatenates the two via `pkgs.writeText`.
- `.sops.yaml` — age recipient list (user + host) and creation rules
- `secrets/` — encrypted YAML (`t14.yaml` holds Wi-Fi PSK + user SSH key). z840 has no sops secrets yet.
- `docs/` — longform notes and drafts; not loaded by the flake
- `reference.md` — full hardware/OS setup guide and 10-item gotcha catalogue for the T14

## Workflow

1. Edit `.nix` files (or assets under `home/patrikpersson/`)
2. **Stage new files first**: `git add path/to/new.nix`. The flake evaluator only sees git-tracked files; untracked paths fail with `path does not exist`.
3. Validate: `nix flake check`
4. Apply: `nh os switch` on the host being rebuilt (preferred — closure diff + nice output), or `sudo nixos-rebuild switch --flake <flake-path>#<host>`. Either way, Claude must hand off — no sudo from tools.
   - On t14: flake lives at `/etc/nixos`, so `nh os switch` Just Works and the long-form is `sudo nixos-rebuild switch --flake /etc/nixos#t14`.
   - On z840: flake lives at `~/nixos-config`, so the long-form is `sudo nixos-rebuild switch --flake ~/nixos-config#z840`. (`programs.nh.flake` is set to that path so `nh os switch` works too.)
5. Rollback: pick an older generation at the bootloader, or `sudo nixos-rebuild switch --rollback`.

## Repo conventions

- `home.file.*.source` paths must be **relative** to the flake (`./claude/CLAUDE.common.md`), not absolute (`/home/...`). Pure evaluation mode rejects absolute paths.
- **Truly mutable state** — caches and files an app *rewrites at runtime* (e.g. `~/.claude.json`: OAuth tokens, onboarding flags) — is not nix-managed; the read-only store can't hold a file the app needs to overwrite. **Config an app merely exposes a UI for** is a separate case: `~/.claude/settings.json` is nix-managed declaratively via `programs.claude-code` (`home/patrikpersson/claude.nix`), accepting that in-app `/config` edits won't survive a rebuild.
- **Fast-moving packages** come from the `pkgs.unstable.*` overlay (defined in `flake.nix`). Bump with `nix flake update nixpkgs-unstable`.
- **Secrets**: edit via `sops secrets/<host>.yaml` (decrypts in `$EDITOR`, re-encrypts on save). Reference decrypted paths via `config.sops.secrets.X.path`; **never** `builtins.readFile` a sops path — that lands plaintext in the world-readable Nix store. If a host SSH key is ever rotated, run `sops updatekeys secrets/<host>.yaml` or activation fails to decrypt.
- **One commit per logical change.** Imperative subject line ("Add X", "Fix Y"). Push directly to `main` — no PRs.
- **Per-host vs shared code**: keep host-specific config inside `hosts/<host>/default.nix`; only promote to `modules/nixos/` once a second host needs the same thing. Same for home-manager — t14 desktop bits stay in `home/patrikpersson/default.nix` and `hyprland.nix`/`theming.nix`/`desktop-shell.nix`; z840 imports only the CLI-relevant pieces via `server.nix`.

## Maintenance

**Keep this file current as part of the same commit when structure changes.** Triggers: new flake input, new host added, new top-level dir, new module in `modules/nixos/`, new convention worth codifying, workflow change (e.g. a new rebuild path). Leave non-structural details (specific package additions, version bumps) out — those live in commit messages and `handover.md`. If `handover.md` records "step N done", check whether this file's Layout/Workflow/Conventions sections still reflect reality.

## Where to look

- `handover.md` — current session-to-session state and roadmap
- `reference.md` — full setup rationale, BIOS settings, install procedure, 10 known T14-on-NixOS gotchas
- `docs/drafts/` — open architectural questions (dotfiles-vs-Nix integration)
- Auto-memory: `~/.claude/projects/<cwd-encoded>/memory/` — rolling project state across sessions, keyed by the cwd Claude Code was invoked from
