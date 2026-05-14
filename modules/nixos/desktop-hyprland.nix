{ config, lib, pkgs, ... }:

{
  # Hyprland: Wayland tiling compositor. Use the nixpkgs build (not the
  # upstream flake) to keep mesa/wlroots versions consistent with the
  # rest of the system — version-skew there manifests as FPS/lag bugs.
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # NIXOS_OZONE_WL=1 makes Electron/Chromium apps render directly on
  # Wayland instead of XWayland — fixes HiDPI scaling and pointer lag
  # in VS Code, Slack, Discord, Chromium.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # xdg portals: file pickers, screen-share negotiation, screenshot UI.
  # The hyprland portal handles wlr-screencopy (OBS, Zoom screen share);
  # the gtk portal handles file dialogs from GTK apps.
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
  };

  # Polkit: GUI privilege prompts (mount removable disk, suspend from a
  # locked session, etc.). The user-side agent is started from the
  # Hyprland exec-once list — see home-manager hyprland.nix.
  security.polkit.enable = true;

  # Display manager: greetd + tuigreet. Tiny Rust login prompt that
  # execs Hyprland directly. Replaces GDM, which would otherwise pull
  # in most of GNOME just to draw the login screen.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
      user = "greeter";
    };
  };

  # Userland Hyprland needs but doesn't install itself. waybar / mako /
  # hyprpaper plus the lock/idle/OSD/clipboard services are installed
  # and configured per-user via home-manager (see
  # home/patrikpersson/desktop-shell.nix) — listing them here would
  # duplicate the closure entry under the system profile.
  # pavucontrol = GUI volume mixer, fired by waybar's on-click handler.
  environment.systemPackages = with pkgs; [
    wofi
    grim
    slurp
    wl-clipboard
    polkit_gnome
    pavucontrol
    # GUI logout/shutdown/reboot/lock overlay. Fired from a waybar
    # power button (see home/patrikpersson/desktop-shell.nix). Ships
    # with a sensible default layout at /etc/wlogout/layout.
    wlogout
  ];

  # Font baseline. Required for emoji + CJK rendering in any GTK/Qt
  # app; Liberation covers metric-compatible Office substitutes;
  # symbols-only Nerd Font provides the icon glyphs that waybar /
  # wlogout / similar tools embed in their format strings (without
  # forcing the whole UI into a monospace font).
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    nerd-fonts.symbols-only
  ];

  # Without an explicit fontconfig alias, Pango (and therefore GTK +
  # waybar) treats `font-family: "Noto Sans", "Symbols Nerd Font"` as a
  # whole-string match list rather than a per-glyph fallback chain — so
  # PUA icon codepoints render as .notdef instead of falling through to
  # the symbols font. Registering Symbols Nerd Font in the sans-serif /
  # monospace defaults makes that fallback explicit at the fontconfig
  # layer, where every app picks it up.
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Noto Sans" "Symbols Nerd Font" ];
    monospace = [ "JetBrainsMono Nerd Font Mono" "Symbols Nerd Font Mono" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # dconf is the GSettings backend. GTK apps still use it for theme
  # and font hinting even when GNOME isn't running.
  programs.dconf.enable = true;
}
