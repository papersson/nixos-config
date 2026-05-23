# CLAUDE.md

## Environment

- ThinkPad T14 Gen 4 Intel, NixOS 25.11 (Xantusia), kernel `pkgs.linuxPackages_latest`
- User: `patrikpersson`. Shell: `zsh`. Prompt: starship. Jumps: zoxide.
- Desktop: Hyprland on Wayland (greetd + tuigreet as the login manager). Terminal: Ghostty. Status bar: waybar; notifications: mako; wallpaper: hyprpaper.
- Hyprland keybinds + compositor settings live in `/etc/nixos/home/patrikpersson/hyprland.nix`; the rest of the shell (bar, notifications, wallpaper, lock/idle, OSD, clipboard) in `desktop-shell.nix` beside it. When asked "how do I do X in Hyprland" (keybinds, workflows, what a shortcut does), read that file first — the config is customised, don't answer from upstream defaults.
- System config: flake at `/etc/nixos`. User-writable for edits; rebuilds need sudo.
