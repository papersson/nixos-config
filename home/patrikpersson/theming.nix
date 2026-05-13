{ config, pkgs, lib, ... }:

{
  # GTK theme. Without GNOME's settings daemon writing dconf, GTK 3/4
  # apps fall back to last-decade defaults. Setting `gtk.theme` here
  # writes ~/.config/gtk-{3,4}.0/settings.ini so every GTK app picks
  # up Adwaita-dark consistently.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    font = {
      # Noto Sans is already in the system fonts.packages set; no extra
      # package needed here.
      name = "Noto Sans";
      size = 11;
    };
  };

  # Qt theming. Qt apps (KeePassXC, OBS, Telegram desktop, qBittorrent)
  # don't read GTK config — they need their own platform theme plugin.
  # `adwaita` installs qt5/qt6 styles that match the GTK Adwaita look,
  # so the two toolkits stay visually consistent.
  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita";
  };

  # Cursor theme. Hyprland reads XCursor; without an explicit theme
  # the tiny X11 default shows up, especially noticeable at 1.25×
  # fractional scaling. `home.pointerCursor` exports XCURSOR_THEME
  # and XCURSOR_SIZE — propagated into Hyprland via the systemd
  # `--all` env import already set in hyprland.nix. gtk.enable +
  # x11.enable also write the theme into the GTK + X11 config so
  # XWayland apps pick it up too.
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };
}
