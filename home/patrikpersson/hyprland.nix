{ config, pkgs, lib, ... }:

{
  wayland.windowManager.hyprland = {
    # The system module (modules/nixos/desktop-hyprland.nix) installs
    # the Hyprland binary and portal. package = null + portalPackage =
    # null tells home-manager to only write ~/.config/hypr/hyprland.conf
    # and not pull its own copy.
    enable = true;
    package = null;
    portalPackage = null;

    # Propagate the full session environment (DBUS_SESSION_BUS_ADDRESS,
    # WAYLAND_DISPLAY, XDG_*) into systemd user units. Without this the
    # tray, portals, and notification daemon often start with a stale
    # or empty environment and silently misbehave.
    systemd.variables = [ "--all" ];

    settings = {
      "$mod" = "SUPER";

      # The T14's internal panel is eDP-1 at 1920x1200. 1.25× fractional
      # scaling produces a 1536×960 logical resolution — comfortable
      # text size while keeping HiDPI-crisp rendering.
      monitor = ",preferred,auto,1.25";

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
          tap-to-click = true;
          clickfinger_behavior = true;
        };
      };

      gestures.workspace_swipe = true;

      # XF86 media keys. brightnessctl + playerctl ship from the t14
      # thinkpad module; wpctl is part of pipewire.
      bindel = [
        ",XF86MonBrightnessUp,   exec, brightnessctl s 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl s 5%-"
        ",XF86AudioRaiseVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute,         exec, wpctl set-mute   @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute,      exec, wpctl set-mute   @DEFAULT_AUDIO_SOURCE@ toggle"
        ",XF86AudioPlay,         exec, playerctl play-pause"
        ",XF86AudioNext,         exec, playerctl next"
        ",XF86AudioPrev,         exec, playerctl previous"
      ];

      bind = [
        # Apps
        "$mod, Return, exec, ghostty"
        "$mod, D,      exec, wofi --show drun"
        "$mod, L,      exec, swaylock -f -c 000000"
        # Window management
        "$mod, Q,      killactive,"
        "$mod, F,      fullscreen,"
        "$mod SHIFT, Q, exit,"
        # Region screenshot to clipboard
        "$mod SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"
        # Focus movement (arrows)
        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"
        # Workspaces 1–5
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # Session autostart. waybar = top bar, mako = notification daemon,
      # polkit agent = GUI privilege prompts. swayidle locks the screen
      # at 5 min, turns the display off at 10 min, and locks before
      # suspend so a stolen laptop on resume hits the lock prompt.
      exec-once = [
        "waybar"
        "mako"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "swayidle -w timeout 300 'swaylock -f -c 000000' timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on' before-sleep 'swaylock -f -c 000000'"
      ];
    };
  };
}
