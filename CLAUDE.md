# CLAUDE.md — NixOS config repo

This is the flake configuring the `t14` host. Single user (`patrikpersson`), single host. NixOS 25.11.

## Layout

- `flake.nix` — inputs (nixpkgs 25.11, nixpkgs-unstable, home-manager release-25.11, nixos-hardware, sops-nix) and the `nixosConfigurations.t14` output
- `flake.lock` — pinned input revisions; commit alongside `flake.nix`
- `hosts/t14/` — host config + auto-generated `hardware-configuration.nix`
- `modules/nixos/` — reusable system modules (T14 hardware tunables, Hyprland desktop + greetd, declarative Wi-Fi via sops)
- `home/patrikpersson/` — home-manager user config and bundled assets (`claude/`, `starship.toml`)
- `.sops.yaml` — age recipient list (user + host) and creation rules
- `secrets/` — encrypted YAML (`t14.yaml` holds Wi-Fi PSK + user SSH key)
- `docs/` — longform notes and drafts; not loaded by the flake
- `reference.md` — full hardware/OS setup guide and 10-item gotcha catalogue for this machine

## Workflow

1. Edit `.nix` files (or assets under `home/patrikpersson/`)
2. **Stage new files first**: `git add path/to/new.nix`. The flake evaluator only sees git-tracked files; untracked paths fail with `path does not exist`.
3. Validate: `nix flake check`
4. Apply: `nh os switch` (preferred — closure diff + nice output), or `sudo nixos-rebuild switch --flake /etc/nixos#t14`. Either way, Claude must hand off — no sudo from tools.
5. Rollback: pick an older generation at the bootloader, or `sudo nixos-rebuild switch --rollback`.

## Repo conventions

- `home.file.*.source` paths must be **relative** to the flake (`./claude/CLAUDE.md`), not absolute (`/home/...`). Pure evaluation mode rejects absolute paths.
- **Mutable-state config files** (e.g. `~/.claude/settings.json`) are written directly to disk, not managed by home-manager. The nix store is read-only; apps that mutate their own config can't be symlinked into it.
- **Fast-moving packages** come from the `pkgs.unstable.*` overlay (defined in `flake.nix`). Bump with `nix flake update nixpkgs-unstable`.
- **Secrets**: edit via `sops secrets/t14.yaml` (decrypts in `$EDITOR`, re-encrypts on save). Reference decrypted paths via `config.sops.secrets.X.path`; **never** `builtins.readFile` a sops path — that lands plaintext in the world-readable Nix store. If the host SSH key is ever rotated, run `sops updatekeys secrets/t14.yaml` or activation fails to decrypt.
- **One commit per logical change.** Imperative subject line ("Add X", "Fix Y"). Push directly to `main` — no PRs.

## Maintenance

**Keep this file current as part of the same commit when structure changes.** Triggers: new flake input, new top-level dir, new module in `modules/nixos/`, new convention worth codifying, workflow change (e.g. a new rebuild path). Leave non-structural details (specific package additions, version bumps) out — those live in commit messages and `handover.md`. If `handover.md` records "step N done", check whether this file's Layout/Workflow/Conventions sections still reflect reality.

## Where to look

- `handover.md` — current session-to-session state and roadmap
- `reference.md` — full setup rationale, BIOS settings, install procedure, 10 known T14-on-NixOS gotchas
- `docs/drafts/` — open architectural questions (dotfiles-vs-Nix integration)
- Auto-memory: `/home/patrikpersson/.claude/projects/-etc-nixos/memory/` — rolling project state across sessions
