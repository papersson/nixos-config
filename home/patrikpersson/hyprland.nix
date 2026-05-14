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

      # Monitor layout, left to right: laptop · LG 4K · Acer 1440p.
      # Externals are matched by `desc:` rather than DP-N connector
      # index — the index shifts when the dock re-enumerates, the
      # description doesn't. The desc strings are deliberately trimmed
      # to a unique *prefix*: Hyprland does partial matching, and the
      # Acer's full description ends in "#ASNuK+hpntPd" — a literal `#`
      # that Hyprland's parser treats as a line comment, silently
      # truncating the monitor line. Keep these prefixes `#`-free.
      # Positions are in *scaled* (logical) pixels:
      #   eDP-1  1920×1200 @1.25  → 1536×960 logical, at 0,240
      #   DP-3   3840×2160 @1.5   → 2560×1440 logical, at 1536,0
      #   DP-4   2560×1440 @1     → 2560×1440 logical, at 4096,0
      # The laptop gets y=240 so its 960px-tall logical area is centred
      # against the 1440px monitors — cursor crosses edges mid-height.
      # The Acer is a 144 Hz panel; `preferred` picks 60, so pin @144.
      # Trailing catch-all keeps any unknown display usable at 1×.
      monitor = [
        "eDP-1, 1920x1200@60, 0x240, 1.25"
        "desc:LG Electronics LG HDR 4K, 3840x2160@60, 1536x0, 1.5"
        "desc:Acer Technologies XB271HU, 2560x1440@144, 4096x0, 1"
        ", preferred, auto, 1"
      ];

      # Workspaces are pinned to monitors: 1–3 laptop, 4–6 the 4K,
      # 7–9 the Acer. `default:true` makes each monitor open on the
      # first of its range. Terminals live on the 4K (ws 4–6), browser
      # on the Acer (ws 7–9), laptop is the spare (ws 1–3). When the
      # dock is absent these rules simply fall back to the laptop.
      workspace = [
        "1, monitor:eDP-1, default:true"
        "2, monitor:eDP-1"
        "3, monitor:eDP-1"
        "4, monitor:desc:LG Electronics LG HDR 4K, default:true"
        "5, monitor:desc:LG Electronics LG HDR 4K"
        "6, monitor:desc:LG Electronics LG HDR 4K"
        "7, monitor:desc:Acer Technologies XB271HU, default:true"
        "8, monitor:desc:Acer Technologies XB271HU"
        "9, monitor:desc:Acer Technologies XB271HU"
      ];

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
        # Zen always opens on the browser workspace (ws 7, the Acer).
        # Only the browser is pinned — terminals stay unpinned so they
        # open on whatever monitor is focused.
        "workspace 7, class:^(zen-beta)$"
      ];

      # XF86 media keys. Brightness + volume up/down repeat while held
      # (bindel) and route through swayosd-client, which performs the
      # change *and* shows an on-screen popup (see services.swayosd in
      # desktop-shell.nix). playerctl ships from the t14 thinkpad module.
      bindel = [
        ",XF86MonBrightnessUp,   exec, swayosd-client --brightness raise"
        ",XF86MonBrightnessDown, exec, swayosd-client --brightness lower"
        ",XF86AudioRaiseVolume,  exec, swayosd-client --output-volume raise"
        ",XF86AudioLowerVolume,  exec, swayosd-client --output-volume lower"
      ];

      # Non-repeating, and still fire on the lock screen (bindl). Mute
      # toggles and caps-lock also show a swayosd popup; the caps-lock
      # sleep lets the LED state settle before swayosd-client reads it.
      bindl = [
        ",XF86AudioMute,    exec, swayosd-client --output-volume mute-toggle"
        ",XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle"
        ",XF86AudioPlay,    exec, playerctl play-pause"
        ",XF86AudioNext,    exec, playerctl next"
        ",XF86AudioPrev,    exec, playerctl previous"
        ", Caps_Lock,       exec, sleep 0.1 && swayosd-client --caps-lock"
      ];

      bind = [
        # Apps
        "$mod, Return, exec, ghostty"
        "$mod, B,      exec, zen-beta"
        "$mod, D,      exec, wofi --show drun"
        # Clipboard history picker — cliphist's two watch services
        # (desktop-shell.nix) feed this list; decode + copy on select.
        "$mod, C,      exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
        # Lock via logind so hypridle's lock_cmd runs hyprlock (one path
        # for manual lock, idle-timeout lock, and before-suspend lock).
        "$mod, Escape, exec, loginctl lock-session"
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

      # Session autostart. waybar / mako / hyprpaper / hypridle / swayosd
      # / cliphist are all systemd user services now (see
      # desktop-shell.nix), so they restart cleanly on crash. Only the
      # polkit agent stays as exec-once — it has no HM systemd module.
      exec-once = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        # Start focused on the 4K (the primary), not whatever monitor
        # Hyprland enumerates first. No-op when the dock is absent.
        "hyprctl dispatch focusmonitor desc:LG Electronics LG HDR 4K"
      ];
    };
  };
}
