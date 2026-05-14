{ config, pkgs, lib, ... }:

let
  # NixOS-artwork ships several wallpapers under
  # ${pkg}/share/backgrounds/nixos/. simple-dark-gray pairs well with
  # the Adwaita-dark theme set in theming.nix.
  wallpaper = "${pkgs.nixos-artwork.wallpapers.simple-dark-gray}/share/backgrounds/nixos/nix-wallpaper-simple-dark-gray.png";
in
{
  # Wallpaper daemon. Hyprland-native, runs as a user systemd service
  # via home-manager. Per-monitor + per-workspace switching via
  # `hyprctl hyprpaper wallpaper`. ipc=on lets us script changes later.
  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "on";
      preload = [ wallpaper ];
      # Empty monitor name (",path") means apply to every output.
      wallpaper = [ ", ${wallpaper}" ];
    };
  };

  # Notification daemon. Mako reads ~/.config/mako/config (HM writes
  # it from settings). Nord-adjacent palette to match Adwaita-dark
  # without looking like raw GTK fallback. anchor=top-right puts
  # notifications under the waybar clock area.
  services.mako = {
    enable = true;
    settings = {
      "border-color" = "#5e81ac";
      "background-color" = "#2e3440";
      "text-color" = "#eceff4";
      "border-radius" = 6;
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
      height = 32;
      spacing = 4;

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

    # CSS lives inline so the colour palette stays in one file with the
    # mako/wallpaper picks above. Bumping these later: edit here, save,
    # nh os switch, `systemctl --user restart waybar`.
    style = ''
      * {
        /* Noto Sans for proportional text; Symbols Nerd Font supplies
           the icon glyphs (battery, wifi, power, …) via Pango fallback.
           Listing Symbols last keeps the bar's text proportional while
           still rendering U+E000-F8FF PUA icons. */
        font-family: "Noto Sans", "Symbols Nerd Font";
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(46, 52, 64, 0.92);
        color: #eceff4;
        border-bottom: 2px solid #5e81ac;
      }

      #workspaces button {
        padding: 0 8px;
        background: transparent;
        color: #d8dee9;
        border-radius: 0;
      }
      #workspaces button.active {
        background: #5e81ac;
        color: #eceff4;
      }
      #workspaces button:hover {
        background: rgba(94, 129, 172, 0.4);
      }

      #window {
        padding: 0 10px;
        color: #d8dee9;
      }

      #clock {
        padding: 0 12px;
        font-weight: bold;
      }

      #battery, #network, #pulseaudio, #tray, #custom-power {
        padding: 0 10px;
      }

      #custom-power {
        color: #bf616a;
        font-size: 15px;
      }
      #custom-power:hover {
        background: rgba(191, 97, 106, 0.2);
      }

      #battery.warning  { color: #ebcb8b; }
      #battery.critical { color: #bf616a; }
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
        path = wallpaper;
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
        inner_color = "rgba(46, 52, 64, 0.9)";
        outer_color = "rgba(94, 129, 172, 1.0)";
        check_color = "rgba(163, 190, 140, 1.0)";
        fail_color = "rgba(191, 97, 106, 1.0)";
        font_color = "rgb(236, 239, 244)";
        placeholder_text = "<i>Password…</i>";
      }];

      label = [
        {
          monitor = "";
          text = "$TIME";
          font_size = 64;
          font_family = "Noto Sans";
          color = "rgba(236, 239, 244, 1.0)";
          position = "0, 120";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] date +"%A, %d %B"'';
          font_size = 20;
          font_family = "Noto Sans";
          color = "rgba(216, 222, 233, 1.0)";
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
