{ config, lib, pkgs, ... }:

{
  # GNOME 49 on Wayland. The X11 session was removed upstream in 49;
  # XWayland is still pulled in transitively for X11 client apps.
  # GDM is the matching display manager and handles PAM (including
  # fprintd integration once a fingerprint is enrolled).
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # dconf is the GSettings backend. GNOME's settings infrastructure
  # depends on it at runtime; this option installs the daemon and the
  # user-level CLI tools (`gsettings`, `dconf-editor` via Tweaks).
  programs.dconf.enable = true;

  # X keymap. GDM and the initial GNOME session read this; matching it
  # to the tty `console.keyMap` keeps one source of truth across the
  # text and graphical login paths.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Reasonable font baseline. GNOME defaults to Cantarell for UI, but
  # web browsing without CJK + emoji fallbacks looks broken on many
  # pages. Liberation covers most metric-compatible Office fonts.
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
  ];
}
