# CLAUDE.md

## Environment

- ThinkPad T14 Gen 4 Intel, NixOS 25.11 (Xantusia), kernel `pkgs.linuxPackages_latest`
- User: `patrikpersson`. Shell: `zsh`. Prompt: starship. Jumps: zoxide.
- Desktop: GNOME 49 on Wayland. Terminal: Ghostty.
- System config: flake at `/etc/nixos`. User-writable for edits; rebuilds need sudo.

## NixOS rules

**System and user packages live in Nix.** Never suggest `apt`, `dnf`, `pip install --user`, `npm install -g`, or `brew install` — none of those are how this machine works. To add a package: edit `/etc/nixos`, rebuild.

**Prefer typed modules over config-file drops.** If `programs.X` exists in NixOS or home-manager, use it. Don't write a `home.file` symlink when a real module covers the option. Option search: <https://search.nixos.org/options>, <https://home-manager-options.extranix.com/>.

**Don't manage mutable state via Nix.** Apps that write back to their own config (e.g. `~/.claude/settings.json`) can't be symlinked into the read-only nix store — that breaks them. Write once, leave mutable.

**When suggesting tools, give the Nix path.** Add to the flake and rebuild for persistence; `nix shell nixpkgs#<name>` for one-offs; per-project `devShell` for development environments.

**Rebuilds need sudo — Claude can't run them.** Hand off via `! sudo nixos-rebuild switch --flake /etc/nixos#t14`.

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

## References

- NixOS manual (25.11): <https://nixos.org/manual/nixos/stable/>
- home-manager manual: <https://nix-community.github.io/home-manager/>
- nix.dev tutorials: <https://nix.dev/>
- Option search: <https://search.nixos.org/options>, <https://home-manager-options.extranix.com/>
