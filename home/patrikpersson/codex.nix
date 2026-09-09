{ ... }:

# OpenAI Codex CLI, managed via home-manager's `programs.codex` module.
#
# The binary is `pkgs.codex`, overridden in flake.nix's overlay to the
# official upstream release tarball (pkgs/codex.nix) — nixpkgs builds from
# source and trails upstream by weeks. Bump with `codex-bump`.
#
# `settings` is left empty on purpose: Codex rewrites ~/.codex/config.toml
# itself at runtime (login, model choice, migrations), so it stays mutable
# like ~/.claude.json. Setting `settings` here would turn it into a
# read-only store symlink and clash with the app's own writes.

{
  programs.codex.enable = true;
}
