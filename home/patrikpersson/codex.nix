{ pkgs, ... }:

# OpenAI Codex CLI, managed via home-manager's `programs.codex` module.
#
# The package comes from the `pkgs.unstable` overlay (flake.nix): stable
# 25.11 ships a months-old build and Codex releases several times a week.
# Bump with `nix flake update nixpkgs-unstable`.
#
# `settings` is written to ~/.codex/config.toml in the read-only nix store,
# so changes made through the in-app UI won't persist — edit here and
# rebuild, same as claude.nix. Login state (~/.codex/auth.json) stays
# mutable and untouched.

{
  programs.codex = {
    enable = true;
    package = pkgs.unstable.codex;
    settings = { };
  };
}
