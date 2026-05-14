{ config, pkgs, lib, ... }:

let
  # Single wallpaper source of truth: hyprpaper displays it and matugen
  # derives the colour palette from it. Committed into the repo so pure
  # flake eval can see it. (Anders Jilden — Vernazza, Cinque Terre.)
  wallpaper = ./wallpapers/cinque-terre.jpg;

  # matugen renders a Material You palette from that wallpaper at build
  # time — `config.programs.matugen.theme.colors` is the parsed result
  # (an IFD: eval builds the matugen derivation). Two accessors for the
  # two consumer formats:
  #   css          — raw #rrggbb, for waybar/mako CSS and mako settings
  #   paletteColor — wrapped in rgb(), for Hyprland-format consumers
  #                  like hyprlock
  # See docs/drafts/matugen-dynamic-theming.md.
  css = role: config.programs.matugen.theme.colors.${role}.default.color;
  paletteColor = role: "rgb(${lib.removePrefix "#" (css role)})";
in
{
  # Material You palette generated from the wallpaper above. The module
  # runs matugen inside a derivation at build time (Option 2 / build-time
  # theming from docs/drafts/matugen-dynamic-theming.md) — no runtime
  # daemon, no mutable state. waybar, mako and hyprlock all read it via
  # the `css` / `paletteColor` helpers above.
  programs.matugen = {
    enable = true;
    inherit wallpaper;
    # scheme-content stays faithful to the source image. index 1 picks
    # the warm sunset candidate colour — index 0 is the cool sea/sky,
    # which every scheme desaturates to grey-blue. Net: coral primary,
    # gold tertiary, warm near-black surface.
    type = "scheme-content";
    source_color_index = 1;
    jsonFormat = "hex";
    variant = "dark";
  };

  # Wallpaper daemon. Hyprland-native, runs as a user systemd service
  # via home-manager. Per-monitor + per-workspace switching via
  # `hyprctl hyprpaper wallpaper`. ipc=on lets us script changes later.
  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "on";
      preload = [ "${wallpaper}" ];
      # Empty monitor name (",path") means apply to every output.
      wallpaper = [ ", ${wallpaper}" ];
    };
  };

  # Notification daemon. Mako reads ~/.config/mako/config (HM writes
  # it from settings). Colours come from the matugen palette so pop-ups
  # match the bar. anchor=top-right puts them under the waybar clock.
  services.mako = {
    enable = true;
    settings = {
      "border-color" = css "primary";
      "background-color" = css "surface_container";
      "text-color" = css "on_surface";
      "border-radius" = 8;
      "border-size" = 2;
      "default-timeout" = 5000;
      font = "Noto Sans 10";
      width = 360;
      height = 120;
      padding = 12;
      margin = 10;
      anchor = "top-right";
      "max-icon-size" = 48;
    };
  };

  # Status bar. systemd.enable=true wires waybar as a user service —
  # restarts cleanly on crash, inherits the Wayland/DBUS env via the
  # hyprland module's systemd.variables = "--all".
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 6;
      # Lift the bar off the screen edges so it reads as a floating
      # rounded panel (border-radius set in `style` below).
      margin-top = 6;
      margin-left = 8;
      margin-right = 8;

      modules-left = [ "hyprland/workspaces" "hyprland/window" ];
      modules-center = [ "clock" ];
      modules-right = [
        "tray"
        "pulseaudio"
        "network"
        "battery"
        "custom/power"
      ];

      "hyprland/workspaces" = {
        format = "{name}";
        on-click = "activate";
        all-outputs = true;
      };

      "hyprland/window" = {
        format = "{}";
        max-length = 60;
        separate-outputs = true;
      };

      clock = {
        # Matches the swedish-living timezone but US-style English labels.
        format = "{:%a %d %b  %H:%M}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };

      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{capacity}% {icon}";
        format-charging = "{capacity}% ";
        format-plugged = "{capacity}% ";
        format-icons = [ "" "" "" "" "" ];
      };

      network = {
        format-wifi = "{essid} ({signalStrength}%) ";
        format-ethernet = "{ipaddr} ";
        format-disconnected = "disconnected ⚠";
        tooltip-format = "{ifname}: {ipaddr}";
      };

      pulseaudio = {
        format = "{volume}% {icon}";
        format-muted = "muted ";
        format-icons = {
          headphone = "";
          default = [ "" "" "" ];
        };
        on-click = "pavucontrol";
      };

      tray = {
        spacing = 10;
      };

      # Power button → opens wlogout, a full-screen overlay with
      # lock / logout / suspend / reboot / shutdown buttons. The
      # nerd-font glyph below is the standard power icon.
      "custom/power" = {
        format = "";
        tooltip = false;
        on-click = "wlogout";
      };
    };

    # CSS inline so the bar's structure stays in one file. Colours are
    # the matugen palette via `css` (see the `let` block) — the bar
    # re-tints whenever the wallpaper changes and the flake is rebuilt.
    style = ''
      * {
        /* Noto Sans for proportional text; Symbols Nerd Font supplies
           the icon glyphs (battery, wifi, power, …) via Pango fallback. */
        font-family: "Noto Sans", "Symbols Nerd Font";
        font-size: 13px;
        min-height: 0;
      }

      /* Floating rounded panel — margins in settings.mainBar lift it
         off the screen edges, border-radius rounds it. */
      window#waybar {
        background: ${css "surface"};
        border: 1px solid ${css "outline_variant"};
        border-radius: 12px;
        color: ${css "on_surface"};
      }

      /* Workspaces: an accent pill on the active workspace. */
      #workspaces {
        margin: 0 4px;
      }
      #workspaces button {
        padding: 0 9px;
        margin: 4px 2px;
        border: none;
        border-radius: 8px;
        box-shadow: none;
        background: transparent;
        color: ${css "on_surface_variant"};
      }
      #workspaces button.active {
        background: ${css "primary"};
        color: ${css "on_primary"};
      }
      #workspaces button:hover {
        background: ${css "surface_container_high"};
        color: ${css "on_surface"};
      }

      #window {
        padding: 0 8px;
        color: ${css "on_surface_variant"};
      }

      #clock {
        padding: 0 14px;
        font-weight: bold;
        color: ${css "primary"};
      }

      /* Right-side status modules: a chip each. */
      #pulseaudio,
      #network,
      #battery,
      #custom-power {
        padding: 0 10px;
        margin: 4px 2px;
        border-radius: 8px;
        background: ${css "surface_container"};
        color: ${css "on_surface"};
      }
      #tray {
        padding: 0 8px;
        margin: 4px 2px;
      }

      #custom-power {
        color: ${css "primary"};
        font-size: 15px;
      }
      #custom-power:hover {
        background: ${css "error"};
        color: ${css "on_primary"};
      }

      #battery.warning  { color: ${css "tertiary"}; }
      #battery.critical { color: ${css "error"}; }
    '';
  };

  # Idle daemon. Replaces the old swayidle exec-once string with a typed
  # systemd user service. hypridle listens for the logind Lock/Unlock
  # and sleep signals, so `loginctl lock-session` (bound to $mod+Escape
  # in hyprland.nix, and fired before suspend) routes through here to
  # start hyprlock.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      # 5 min → lock, 10 min → screen off, 15 min → suspend.
      listener = [
        { timeout = 300; on-timeout = "loginctl lock-session"; }
        {
          timeout = 600;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        { timeout = 900; on-timeout = "systemctl suspend"; }
      ];
    };
  };

  # Lock screen. Hyprland-native, GPU-accelerated — replaces swaylock.
  # Background is the same wallpaper as hyprpaper, blurred; palette
  # matches the Nord-ish waybar/mako theme above.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 0;
        ignore_empty_input = true;
      };

      background = [{
        path = "${wallpaper}";
        blur_passes = 3;
        blur_size = 8;
      }];

      input-field = [{
        monitor = "";
        size = "300, 50";
        position = "0, -80";
        halign = "center";
        valign = "center";
        outline_thickness = 2;
        rounding = 8;
        dots_center = true;
        fade_on_empty = false;
        # Material You roles from matugen (see paletteColor above).
        inner_color = paletteColor "surface";
        outer_color = paletteColor "primary";
        check_color = paletteColor "tertiary";
        fail_color = paletteColor "error";
        font_color = paletteColor "on_surface";
        placeholder_text = "<i>Password…</i>";
      }];

      label = [
        {
          monitor = "";
          text = "$TIME";
          font_size = 64;
          font_family = "Noto Sans";
          color = paletteColor "primary";
          position = "0, 120";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] date +"%A, %d %B"'';
          font_size = 20;
          font_family = "Noto Sans";
          color = paletteColor "on_surface";
          position = "0, 50";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # On-screen display for volume / brightness / caps-lock. The XF86
  # media keys in hyprland.nix call swayosd-client, which performs the
  # change *and* draws the popup — replacing the silent brightnessctl /
  # wpctl calls. Runs swayosd-server as a user service.
  services.swayosd.enable = true;

  # Clipboard history. Two `wl-paste --watch` user services record text
  # and image copies; `$mod+C` (hyprland.nix) lists them through wofi.
  services.cliphist.enable = true;
}
