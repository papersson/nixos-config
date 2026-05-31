{ pkgs, lib, catp, ... }:

let
  # Wallpaper file. Used by hyprpaper (visible desktop background) and
  # hyprlock (blurred lock-screen background). Committed into the repo
  # so pure flake eval can see it. (Anders Jilden — Vernazza, Cinque Terre.)
  wallpaper = ./wallpapers/cinque-terre.jpg;

  # hyprlock wants colours in Hyprland's rgb() format. Small wrapper so
  # the consumers below stay readable: `rgb catp.mauve` is nicer than
  # an inline `"rgb(${lib.removePrefix "#" catp.mauve})"`.
  rgb = c: "rgb(${lib.removePrefix "#" c})";

  # Nerd Font icon glyphs, referenced by codepoint. Raw glyphs live in
  # the Private Use Area (U+E000–U+F8FF); the editing pipeline silently
  # strips PUA characters on save — which is why every waybar icon kept
  # vanishing to an empty string. This keeps the source pure-ASCII:
  # builtins.fromJSON decodes the \u escape into the real char at eval
  # time, and the glyph only ever exists in the generated config. BMP
  # codepoints only (4 hex digits) — covers the Font Awesome set used here.
  glyph = cp: builtins.fromJSON ''"\u${cp}"'';
in
{
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
  # it from settings). Catppuccin Mocha palette via the `catp` arg
  # (palette.nix). anchor=top-right puts pop-ups under the waybar clock.
  services.mako = {
    enable = true;
    settings = {
      "border-color" = catp.mauve;
      "background-color" = catp.surface0;
      "text-color" = catp.text;
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
        format-charging = "{capacity}% ${glyph "f0e7"}";
        format-plugged = "{capacity}% ${glyph "f1e6"}";
        # Battery levels, empty → full (nf-fa-battery_0 … battery_4).
        format-icons = [
          (glyph "f244")
          (glyph "f243")
          (glyph "f242")
          (glyph "f241")
          (glyph "f240")
        ];
      };

      network = {
        format-wifi = "{essid} ({signalStrength}%) ${glyph "f1eb"}";
        format-ethernet = "{ipaddr} ${glyph "f0e8"}";
        format-disconnected = "disconnected ⚠";
        tooltip-format = "{ifname}: {ipaddr}";
      };

      pulseaudio = {
        format = "{volume}% {icon}";
        format-muted = "muted ${glyph "f026"}";
        format-icons = {
          headphone = glyph "f025";
          default = [ (glyph "f026") (glyph "f027") (glyph "f028") ];
        };
        on-click = "pavucontrol";
      };

      tray = {
        spacing = 10;
      };

      # Power button → opens wlogout, a full-screen overlay with
      # lock / logout / suspend / reboot / shutdown buttons. Icon is
      # nf-fa-power_off (U+F011) built via the `glyph` helper.
      "custom/power" = {
        format = glyph "f011";
        tooltip = false;
        on-click = "wlogout";
      };
    };

    # CSS inline so the bar's structure stays in one file. Colours are
    # the Catppuccin Mocha palette via `catp` (palette.nix). Layout
    # signature borrowed from bautistaaa/dotfiles: translucent bar +
    # mauve accent fills on the eye-catchers (active workspace, focused
    # window) + translucent surface0 chips on status modules.
    style = ''
      * {
        /* Noto Sans for proportional text; Symbols Nerd Font supplies
           the icon glyphs (battery, wifi, power, …) via Pango fallback. */
        font-family: "Noto Sans", "Symbols Nerd Font";
        font-size: 13px;
        min-height: 0;
      }

      /* Floating rounded panel — margins in settings.mainBar lift it
         off the screen edges, border-radius rounds it. The alpha() blend
         on the background is paired with a Hyprland `layerrule = blur,
         waybar` (hyprland.nix) so windows behind the bar diffuse through
         it instead of just showing semi-transparent crust colour.
         Border picks up mauve at low alpha for a soft accent edge. */
      window#waybar {
        background: alpha(${catp.crust}, 0.72);
        border: 1px solid alpha(${catp.mauve}, 0.35);
        border-radius: 16px;
        color: ${catp.text};
      }

      /* Workspaces. Active workspace is a solid mauve chip — the
         strongest accent on the bar. Inactive workspaces have no chrome;
         hover lifts a soft mauve tint. */
      #workspaces {
        margin: 0 6px;
      }
      #workspaces button {
        padding: 0 10px;
        margin: 5px 3px;
        border: none;
        border-radius: 8px;
        box-shadow: none;
        background: transparent;
        color: ${catp.subtext0};
      }
      #workspaces button.active {
        background: ${catp.mauve};
        color: ${catp.crust};
      }
      #workspaces button:hover {
        background: alpha(${catp.mauve}, 0.30);
        color: ${catp.text};
      }

      /* Focused window — second accent. Solid mauve chip carrying the
         window title. Empty title collapses to no module on most waybar
         versions; if the chip ever looks awkward, swap to a custom/exec
         script (bautistaaa does this) for nicer formatting. */
      #window {
        padding: 0 12px;
        margin: 5px 4px;
        border-radius: 8px;
        background: ${catp.mauve};
        color: ${catp.crust};
        font-weight: bold;
      }

      /* Centre clock — minimal, lets workspace/window chips be the
         visual anchors. */
      #clock {
        padding: 0 14px;
        margin: 5px 4px;
        font-weight: bold;
        color: ${catp.text};
      }

      /* Right-side status modules: a translucent surface0 chip each.
         Matches bautistaaa's rgba(49, 50, 68, 0.85) exactly. */
      #pulseaudio,
      #network,
      #battery,
      #custom-power {
        padding: 0 12px;
        margin: 5px 4px;
        border-radius: 8px;
        background: alpha(${catp.surface0}, 0.85);
        color: ${catp.text};
      }
      #tray {
        padding: 0 8px;
        margin: 5px 4px;
      }

      #custom-power {
        color: ${catp.mauve};
        font-size: 15px;
        /* Icon-only module — force the symbols font directly instead of
           relying on the Noto-Sans→Symbols Pango fallback chain. */
        font-family: "Symbols Nerd Font";
      }
      #custom-power:hover {
        background: ${catp.red};
        color: ${catp.crust};
      }

      #battery.warning  { color: ${catp.peach}; }
      #battery.critical { color: ${catp.red}; }
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
  # matches the Catppuccin waybar/mako theme above.
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
        inner_color = rgb catp.crust;
        outer_color = rgb catp.mauve;
        check_color = rgb catp.peach;
        fail_color = rgb catp.red;
        font_color = rgb catp.text;
        placeholder_text = "<i>Password…</i>";
      }];

      label = [
        {
          monitor = "";
          text = "$TIME";
          font_size = 64;
          font_family = "Noto Sans";
          color = rgb catp.mauve;
          position = "0, 120";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] date +"%A, %d %B"'';
          font_size = 20;
          font_family = "Noto Sans";
          color = rgb catp.text;
          position = "0, 50";
          halign = "center";
          valign = "center";
        }
        # MPRIS now-playing line. playerctl exits non-zero with no
        # players, leaving stdout empty → hyprlock renders nothing.
        # 5-second poll is cheap on the locked screen. playerctl ships
        # from the thinkpad-t14 module so it's already in PATH.
        {
          monitor = "";
          text = ''cmd[update:5000] playerctl metadata --format "{{ artist }} — {{ title }}" 2>/dev/null'';
          font_size = 14;
          font_family = "Noto Sans";
          color = rgb catp.subtext0;
          position = "0, 80";
          halign = "center";
          valign = "bottom";
        }
      ];
    };
  };

  # On-screen display for volume / brightness / caps-lock. The XF86
  # media keys in hyprland.nix call swayosd-client, which performs the
  # change *and* draws the popup — replacing the silent brightnessctl /
  # wpctl calls. Runs swayosd-server as a user service.
  services.swayosd.enable = true;

  # swayosd doesn't have a style option on the HM module, so write the
  # GTK CSS directly. Matches the waybar/mako visual language: rounded
  # surface0 pill with a mauve progress fill.
  xdg.configFile."swayosd/style.css".text = ''
    window#osd {
      background-color: ${catp.surface0};
      border: 1px solid ${catp.surface1};
      border-radius: 12px;
      padding: 12px 16px;
      color: ${catp.text};
    }

    window#osd image {
      color: ${catp.text};
      min-height: 24px;
      min-width: 24px;
    }

    window#osd label {
      color: ${catp.text};
    }

    window#osd progressbar {
      min-height: 8px;
    }
    window#osd progressbar trough {
      background-color: ${catp.surface1};
      border: none;
      border-radius: 4px;
      min-height: 8px;
    }
    window#osd progressbar progress {
      background-color: ${catp.mauve};
      border: none;
      border-radius: 4px;
      min-height: 8px;
    }
  '';

  # Clipboard history. Two `wl-paste --watch` user services record text
  # and image copies; `$mod+C` (hyprland.nix) lists them through wofi.
  services.cliphist.enable = true;

  # Power overlay. Fired from the waybar power chip ($mod+SHIFT+E too,
  # in hyprland.nix). Owned here so the style.css and layout follow the
  # Catppuccin palette — previously wlogout was installed at the system
  # level with its default unstyled overlay. Icons are pulled from the
  # bundled package data dir via background-image url() in the CSS.
  programs.wlogout = {
    enable = true;
    layout = [
      { label = "lock";      action = "loginctl lock-session";           text = "Lock";     keybind = "l"; }
      { label = "logout";    action = "hyprctl dispatch exit";           text = "Logout";   keybind = "e"; }
      { label = "suspend";   action = "systemctl suspend";               text = "Suspend";  keybind = "u"; }
      { label = "hibernate"; action = "systemctl hibernate";             text = "Hiber";    keybind = "h"; }
      { label = "reboot";    action = "systemctl reboot";                text = "Reboot";   keybind = "r"; }
      { label = "shutdown";  action = "systemctl poweroff";              text = "Shutdown"; keybind = "s"; }
    ];
    style = ''
      * {
        font-family: "Noto Sans";
        font-size: 16px;
        background-image: none;
        transition: 200ms;
      }

      window {
        /* GTK CSS alpha() blends an opaque colour with the destination,
           dimming the wallpaper behind the overlay. */
        background-color: alpha(${catp.crust}, 0.85);
      }

      button {
        color: ${catp.text};
        background-color: ${catp.surface0};
        border-radius: 16px;
        border: 1px solid ${catp.surface1};
        margin: 10px;
        background-repeat: no-repeat;
        background-position: center;
        background-size: 25%;
      }

      button:focus, button:active, button:hover {
        background-color: ${catp.mauve};
        color: ${catp.crust};
        border-color: ${catp.mauve};
        outline-style: none;
      }

      /* Bundled icons from the wlogout package's data dir. */
      #lock      { background-image: url("${pkgs.wlogout}/share/wlogout/icons/lock.png"); }
      #logout    { background-image: url("${pkgs.wlogout}/share/wlogout/icons/logout.png"); }
      #suspend   { background-image: url("${pkgs.wlogout}/share/wlogout/icons/suspend.png"); }
      #hibernate { background-image: url("${pkgs.wlogout}/share/wlogout/icons/hibernate.png"); }
      #reboot    { background-image: url("${pkgs.wlogout}/share/wlogout/icons/reboot.png"); }
      #shutdown  { background-image: url("${pkgs.wlogout}/share/wlogout/icons/shutdown.png"); }
    '';
  };

  # App launcher / dmenu picker. Bound to $mod+D (drun) and $mod+C
  # (cliphist via --dmenu) in hyprland.nix. Owned here so the style.css
  # below tracks the Catppuccin palette — previously wofi was installed
  # at the system level with default styling.
  programs.wofi = {
    enable = true;
    settings = {
      width = 600;
      height = 400;
      location = "center";
      show = "drun";
      prompt = "search";
      filter_rate = 100;
      allow_markup = true;
      no_actions = true;
      halign = "fill";
      orientation = "vertical";
      content_halign = "fill";
      insensitive = true;
      allow_images = true;
      image_size = 32;
      gtk_dark = true;
    };
    style = ''
      * {
        font-family: "Noto Sans", "Symbols Nerd Font";
        font-size: 13px;
      }

      window {
        background-color: ${catp.surface0};
        border: 1px solid ${catp.surface1};
        border-radius: 12px;
        color: ${catp.text};
      }

      #input {
        margin: 12px;
        padding: 8px 12px;
        border: 1px solid ${catp.surface1};
        border-radius: 8px;
        background-color: ${catp.surface1};
        color: ${catp.text};
      }
      #input:focus {
        border-color: ${catp.mauve};
      }

      #inner-box {
        margin: 0 6px 6px 6px;
      }
      #outer-box {
        padding: 0;
      }
      #scroll {
        margin: 0;
      }

      #entry {
        padding: 6px 12px;
        margin: 2px 6px;
        border-radius: 8px;
        background: transparent;
        color: ${catp.text};
      }
      #entry:selected {
        background-color: ${catp.mauve};
        color: ${catp.crust};
      }
      #entry image {
        margin-right: 10px;
      }
      #text {
        color: inherit;
      }
    '';
  };
}
