{ pkgs, catp, ... }:

{
  # GTK theme. Without GNOME's settings daemon writing dconf, GTK 3/4
  # apps fall back to last-decade defaults. Setting `gtk.theme` here
  # writes ~/.config/gtk-{3,4}.0/settings.ini so every GTK app picks
  # up Adwaita-dark consistently. extraCss overrides the accent colour
  # roles on top of Adwaita so selection / button highlight / focus
  # rings follow the Catppuccin Mocha mauve accent. libadwaita apps
  # (GTK4) pick this up via @define-color accent_*; GTK3 reads
  # theme_selected_* the same way.
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
    gtk3.extraCss = ''
      @define-color theme_selected_bg_color ${catp.mauve};
      @define-color theme_selected_fg_color ${catp.crust};
    '';
    gtk4.extraCss = ''
      @define-color accent_color ${catp.mauve};
      @define-color accent_bg_color ${catp.mauve};
      @define-color accent_fg_color ${catp.crust};
    '';
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
