# CLAUDE.md — NixOS config repo

This is the flake configuring the `t14` host. Single user (`patrikpersson`), single host. NixOS 25.11.

## Layout

- `flake.nix` — inputs (nixpkgs 25.11, nixpkgs-unstable, home-manager release-25.11, nixos-hardware) and the `nixosConfigurations.t14` output
- `flake.lock` — pinned input revisions; commit alongside `flake.nix`
- `hosts/t14/` — host config + auto-generated `hardware-configuration.nix`
- `modules/nixos/` — reusable system modules (T14 hardware tunables, GNOME desktop)
- `home/patrikpersson/` — home-manager user config and bundled assets (`claude/`, `starship.toml`)
- `docs/` — longform notes and drafts; not loaded by the flake
- `reference.md` — full hardware/OS setup guide and 10-item gotcha catalogue for this machine

## Workflow

1. Edit `.nix` files (or assets under `home/patrikpersson/`)
2. **Stage new files first**: `git add path/to/new.nix`. The flake evaluator only sees git-tracked files; untracked paths fail with `path does not exist`.
3. Validate: `nix flake check`
4. Apply: `sudo nixos-rebuild switch --flake /etc/nixos#t14`. Claude must hand off — no sudo from tools.
5. Rollback: pick an older generation at the bootloader, or `sudo nixos-rebuild switch --rollback`.

## Repo conventions

- `home.file.*.source` paths must be **relative** to the flake (`./claude/CLAUDE.md`), not absolute (`/home/...`). Pure evaluation mode rejects absolute paths.
- **Mutable-state config files** (e.g. `~/.claude/settings.json`) are written directly to disk, not managed by home-manager. The nix store is read-only; apps that mutate their own config can't be symlinked into it.
- **Fast-moving packages** come from the `pkgs.unstable.*` overlay (defined in `flake.nix`). Bump with `nix flake update nixpkgs-unstable`.
- **One commit per logical change.** Imperative subject line ("Add X", "Fix Y"). Push directly to `main` — no PRs.

## Where to look

- `reference.md` — full setup rationale, BIOS settings, install procedure, 10 known T14-on-NixOS gotchas
- `docs/drafts/` — open architectural questions (dotfiles-vs-Nix integration, sops-nix roadmap)
- Auto-memory: `/home/patrikpersson/.claude/projects/-etc-nixos/memory/` — rolling project state across sessions
