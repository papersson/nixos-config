{ config, inputs, pkgs, ... }:

let
  runnerPkgs = inputs.nixpkgs-runner.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in

# Self-hosted GitHub Actions runner for papersson/apps, labelled `z840`, so
# workflows can pick this box with `runs-on: [self-hosted, z840]`.
#
# Non-root on purpose: the module's default DynamicUser with its systemd
# hardening, no extra groups, no sudo. Workflows reach the Nix store through
# the daemon socket like any other user.
#
# Registration: tokenFile holds a one-time registration token (valid 1 h),
# written root-only by
#   gh api -X POST repos/papersson/apps/actions/runners/registration-token \
#     --jq .token | sudo install -m 600 /dev/stdin <tokenFile>
# The runner keeps its own credentials in /var/lib/github-runner/apps after
# the first start, so the token is only needed again when a change to the
# options below forces a re-registration; then mint a fresh one first.
{
  services.github-runners.apps = {
    enable = true;
    url = "https://github.com/papersson/apps";
    name = "z840";
    extraLabels = [ "z840" ];
    replace = true;
    tokenFile = "/var/lib/github-runner-registration/apps.token";

    # Newer runners ship only node24; the module default also asks for node20.
    nodeRuntimes = [ "node24" ];
    # From its own nixpkgs pin, which tracks unstable: see the
    # nixpkgs-runner input in flake.nix for why and how to bump it.
    package = runnerPkgs.github-runner;

    extraPackages = with pkgs; [
      git
      config.nix.package
      bash
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      gnutar
      gzip
      xz
      curl
      jq
      sops
      age
      openssh
      which
      unzip
      # pnpm/action-setup's self-installer runs npm before setup-node does.
      runnerPkgs.nodejs_26
      # GitHub's hosted image ships these and the workflows call them: gh for
      # the Checks ratchet, python3 for .github/scripts/pr-media-embed.sh.
      gh
      python3
      # The repo's scripts call these, which the hosted image also has:
      util-linux # setsid (UI review job), flock
      procps # pgrep, kill
      hostname # hostname
      netcat-openbsd # nc
      diffutils # diff
      file # file
      # scripts/ui.sh (UI review job) prefers chromium from PATH; the Chrome
      # for Testing it downloads otherwise can't run on NixOS.
      chromium
    ];

    # actions/setup-node and pnpm/action-setup download generic Linux
    # binaries; nix-ld (below) runs them. systemd services don't read the
    # session variables nix-ld sets, so pass them to the runner directly.
    extraEnvironment = {
      inherit (config.environment.sessionVariables) NIX_LD NIX_LD_LIBRARY_PATH;
    };
  };

  # System fonts, so the UI review's headless screenshots render text. The
  # host had none outside home-manager, which a DynamicUser can't see.
  fonts.packages = [ pkgs.dejavu_fonts ];

  # nix-ld is already enabled in default.nix; these lists merge with its
  # libraries. Enough for Node and for Playwright's downloaded Chromium
  # (the set nixpkgs' own playwright-chromium patches against, plus fonts).
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    glib
    nss
    nspr
    dbus
    expat
    atk
    at-spi2-atk
    at-spi2-core
    cups
    cairo
    pango
    gtk3
    gobject-introspection
    alsa-lib
    libgbm
    libdrm
    libGL
    vulkan-loader
    libxkbcommon
    fontconfig
    freetype
    pciutils
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    xorg.libxshmfence
  ];
}
