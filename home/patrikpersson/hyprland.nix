{ config, pkgs, lib, ... }:

{
  wayland.windowManager.hyprland = {
    # The system module installs Hyprland + portal. package/portalPackage
    # = null here tells home-manager to only write the conf file.
    enable = true;
    package = null;
    portalPackage = null;

    # Propagate the full session env (DBUS_SESSION_BUS_ADDRESS,
    # WAYLAND_DISPLAY, XDG_*) into systemd user units. Without this,
    # waybar / mako / hyprpaper start with a stale env and misbehave.
    systemd.variables = [ "--all" ];

    settings = {
      "$mod" = "SUPER";

      # T14 internal panel eDP-1 at 1920×1200, 1.25× fractional scaling.
      monitor = ",preferred,auto,1.25";

      # Cursor size — Hyprland reads these env vars at startup. XCURSOR
      # covers XWayland + most apps; HYPRCURSOR is the newer Hyprland-
      # native format if a matching theme is installed (we use XCursor).
      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
      ];

      # Look-and-feel values are the upstream defaults from
      # github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua,
      # tightened on `gaps_out` because 20px is wasteful at 1920×1200.
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(5e81acff) rgba(81a1c1ff) 45deg";
        "col.inactive_border" = "rgba(2e3440aa)";
        resize_on_border = true;
        allow_tearing = false;
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
        rounding_power = 2;
        active_opacity = 1.0;
        inactive_opacity = 1.0;
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
        blur = {
          enabled = true;
          size = 3;
          passes = 1;
          vibrancy = 0.1696;
        };
      };

      # Animation curves + per-layer animation specs from the upstream
      # example. The "easeOutQuint" + "almostLinear" pair is what makes
      # the workspace + fade transitions feel current rather than the
      # 2022-era default exponential ease.
      animations = {
        enabled = true;
        bezier = [
          "easeOutQuint,   0.23, 1,    0.32, 1"
          "easeInOutCubic, 0.65, 0.05, 0.36, 1"
          "linear,         0,    0,    1,    1"
          "almostLinear,   0.5,  0.5,  0.75, 1"
          "quick,          0.15, 0,    0.1,  1"
        ];
        animation = [
          "global,        1, 10,   default"
          "border,        1, 5.39, easeOutQuint"
          "windows,       1, 4.79, easeOutQuint"
          "windowsIn,     1, 4.1,  easeOutQuint, popin 87%"
          "windowsOut,    1, 1.49, linear,       popin 87%"
          "fadeIn,        1, 1.73, almostLinear"
          "fadeOut,       1, 1.46, almostLinear"
          "fade,          1, 3.03, quick"
          "layers,        1, 3.81, easeOutQuint"
          "layersIn,      1, 4,    easeOutQuint, fade"
          "layersOut,     1, 1.5,  linear,       fade"
          "fadeLayersIn,  1, 1.79, almostLinear"
          "fadeLayersOut, 1, 1.39, almostLinear"
          "workspaces,    1, 1.94, almostLinear, fade"
          "workspacesIn,  1, 1.21, almostLinear, fade"
          "workspacesOut, 1, 1.94, almostLinear, fade"
          "zoomFactor,    1, 7,    quick"
        ];
      };

      dwindle = {
        preserve_split = true;
        smart_resizing = true;
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        # Hyprland defaults (600/25) feel sluggish; 250/50 is the typical
        # tiling-WM pick — closer to GNOME/KDE responsiveness.
        repeat_delay = 250;
        repeat_rate = 50;
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
          tap-to-click = true;
          clickfinger_behavior = true;
        };
      };

      # Three-finger horizontal swipe → switch workspace (Hyprland 0.51+
      # unified `gesture` keyword; replaced gestures.workspace_swipe).
      gesture = [
        "3, horizontal, workspace"
      ];

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        # Don't pull the Hyprland default wallpaper — hyprpaper sets ours.
        force_default_wallpaper = 0;
        animate_manual_resizes = true;
        animate_mouse_windowdragging = true;
      };

      # Window rules. v2 form. Float ad-hoc dialogs and pin video PiP.
      windowrulev2 = [
        "float, class:^(pavucontrol)$"
        "float, class:^(blueman-manager)$"
        "float, class:^(nm-connection-editor)$"
        "float, title:^(File Operation Progress)$"
        "float, title:^(Picture-in-Picture)$"
        "pin,   title:^(Picture-in-Picture)$"
      ];

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
        "$mod, Escape, exec, swaylock -f -c 000000"
        "$mod SHIFT, E, exec, wlogout"
        # Window management
        "$mod, Q,      killactive,"
        "$mod, F,      fullscreen,"
        "$mod, V,      togglefloating,"
        "$mod, P,      pseudo,"
        # togglesplit lives on T because J is now focus-down (vim hjkl)
        "$mod, T,      togglesplit,"
        # Cycle windows without thinking about direction (Alt-Tab style)
        "$mod, Tab,       cyclenext,"
        "$mod SHIFT, Tab, cyclenext, prev"
        # Region screenshot to clipboard
        "$mod SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"
        # Focus movement — vim h/j/k/l = left/down/up/right
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"
        # Move the focused window within the tiling tree
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"
        # Resize the focused window in 40px steps
        "$mod CTRL, H, resizeactive, -40 0"
        "$mod CTRL, J, resizeactive,  0 40"
        "$mod CTRL, K, resizeactive,  0 -40"
        "$mod CTRL, L, resizeactive,  40 0"
        # Workspaces 1–9 (was 1–5)
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        # Scroll workspaces with mouse wheel
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up,   workspace, e-1"
        # Special workspace (scratchpad): $mod+S toggles the hidden
        # "magic" workspace; $mod+Alt+S throws the focused window into
        # it. Handy for a stash terminal or notes window. ($mod+Shift+S
        # is taken by the region screenshot, hence Alt for move-to.)
        "$mod, S,     togglespecialworkspace, magic"
        "$mod ALT, S, movetoworkspace, special:magic"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # Session autostart. waybar / mako / hyprpaper are now systemd
      # user services (see desktop-shell.nix) so they restart cleanly
      # on crash. Only the polkit agent and swayidle stay as exec-once
      # since they don't have HM-managed systemd integration.
      exec-once = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "swayidle -w timeout 300 'swaylock -f -c 000000' timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on' before-sleep 'swaylock -f -c 000000'"
      ];
    };
  };
}
