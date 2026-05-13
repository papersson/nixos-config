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
    };

    # CSS lives inline so the colour palette stays in one file with the
    # mako/wallpaper picks above. Bumping these later: edit here, save,
    # nh os switch, `systemctl --user restart waybar`.
    style = ''
      * {
        font-family: "Noto Sans", "JetBrainsMono Nerd Font";
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

      #battery, #network, #pulseaudio, #tray {
        padding: 0 10px;
      }

      #battery.warning  { color: #ebcb8b; }
      #battery.critical { color: #bf616a; }
    '';
  };
}
