# CLAUDE.md

## Environment

- ThinkPad T14 Gen 4 Intel, NixOS 25.11 (Xantusia), kernel `pkgs.linuxPackages_latest`
- User: `patrikpersson`. Shell: `zsh`. Prompt: starship. Jumps: zoxide.
- Desktop: Hyprland on Wayland (greetd + tuigreet as the login manager). Terminal: Ghostty. Status bar: waybar; notifications: mako; wallpaper: hyprpaper.
- Hyprland keybinds + compositor settings live in `/etc/nixos/home/patrikpersson/hyprland.nix`; bar/notifications/wallpaper in `desktop-shell.nix` beside it. When asked "how do I do X in Hyprland" (keybinds, workflows, what a shortcut does), read that file first — the config is customised, don't answer from upstream defaults.
- System config: flake at `/etc/nixos`. User-writable for edits; rebuilds need sudo.

## NixOS rules

**System and user packages live in Nix.** Never suggest `apt`, `dnf`, `pip install --user`, `npm install -g`, or `brew install` — none of those are how this machine works. To add a package: edit `/etc/nixos`, rebuild.

**Prefer typed modules over config-file drops.** If `programs.X` exists in NixOS or home-manager, use it. Don't write a `home.file` symlink when a real module covers the option. Option search: <https://search.nixos.org/options>, <https://home-manager-options.extranix.com/>.

**Don't manage mutable state via Nix.** Apps that write back to their own config (e.g. `~/.claude/settings.json`) can't be symlinked into the read-only nix store — that breaks them. Write once, leave mutable.

**When suggesting tools, give the Nix path.** Add to the flake and rebuild for persistence; `nix shell nixpkgs#<name>` for one-offs; per-project `devShell` for development environments (auto-loaded by direnv when an `.envrc` says `use flake`).

**Rebuilds need sudo — Claude can't run them.** Hand off via `! nh os switch` (works from any directory, includes closure diffs). The long-form `sudo nixos-rebuild switch ...` lives in the project's CLAUDE.md if you need it.

**Secrets are sops-encrypted, not plaintext in the flake.** Never put credentials directly into Nix values, and never `builtins.readFile` a sops path — both land secrets in the world-readable nix store. When working in `/etc/nixos`, see that repo's CLAUDE.md for the YAML filename, edit commands, and rotation steps.

## Working style

- Direct. Concise. Lead with the most important info.
- State uncertainty explicitly. Don't bluff.
- Search first, read full files second, change third.
- Verify changes (run the test, type-check, rebuild). Don't assume.
- Fail fast with clear messages. Don't swallow errors silently.

## Tooling preferences

- Text search: `rg`
- Structural search: `ast-grep`
- File by name: `fd`
- View files: `bat`, `eza` (replaces `ls`)
- JSON: `jq`
- All present on this machine via home-manager.

## Writing style guardrails

- No empty emphasis ("crucial role", "stands as a testament", "watershed moment").
- No promotional language ("breathtaking", "nestled", "captivates").
- No "I hope this helps", "Certainly!", or meta-disclaimers about being an AI.
- Bold sparingly, only for real emphasis. Not for decoration.
- Avoid negative parallelisms — say "X and Y", not "not just X, but Y".

## CLAUDE.md hierarchy

CLAUDE.md files cascade by filesystem location. `~/.claude/CLAUDE.md` (this file) loads in every session; a project's root `CLAUDE.md` loads when cwd is inside that project; a subdirectory's `CLAUDE.md` loads when cwd is under it. Children **supplement**, not replace, parents — everything compounds into the same context.

Use this deliberately. Place each fact at the **narrowest scope where it's still true**:

- Universal preferences, machine-level workflow → global (this file).
- Repo layout, repo-wide conventions, repo-specific file locations → project root CLAUDE.md.
- Subsystem-specific rules (a `secrets/CLAUDE.md` warning about encryption discipline, a `modules/CLAUDE.md` codifying module patterns, a `migrations/CLAUDE.md` for schema-change conventions) → subdirectory CLAUDE.md.

Avoid two failure modes:
- **Duplication**: a fact in a parent is already loaded; restating it in a child creates drift risk when one copy gets updated and the other doesn't.
- **Scope bleed**: a fact in a child is *not* loaded outside that subtree — cross-cutting rules placed there go silent the moment you `cd` away.

When introducing a new rule, ask: "from which directory will future-me be working when this rule applies?" That directory's CLAUDE.md is where it goes. If a project grows a subsystem with its own non-obvious conventions, that's a signal to create a CLAUDE.md inside it rather than expand the root file.

## Maintenance

Keep this file current when the environment shifts. Triggers worth an edit: change to shell / prompt / terminal / desktop, new daily-driver tool added (e.g. `nh`, `direnv`, `sops`), change to how rebuilds happen, change to where packages come from. Skip the trivial — single package additions and version bumps stay out and live in commit messages instead. Project-specific facts go in the project's CLAUDE.md, subsystem-specific facts go deeper; see the Hierarchy section above for placement.

## References

- NixOS manual (25.11): <https://nixos.org/manual/nixos/stable/>
- home-manager manual: <https://nix-community.github.io/home-manager/>
- nix.dev tutorials: <https://nix.dev/>
- Option search: <https://search.nixos.org/options>, <https://home-manager-options.extranix.com/>
