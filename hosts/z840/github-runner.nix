{ config, pkgs, ... }:

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
    ];

    # actions/setup-node and pnpm/action-setup download generic Linux
    # binaries; nix-ld (below) runs them. systemd services don't read the
    # session variables nix-ld sets, so pass them to the runner directly.
    extraEnvironment = {
      inherit (config.environment.sessionVariables) NIX_LD NIX_LD_LIBRARY_PATH;
    };
  };

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
