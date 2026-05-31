{ ... }:

# Catppuccin Mocha palette, exposed as `catp` to every home-manager
# module in this profile via `_module.args`. Consumers read it as:
#
#   { catp, ... }: { ... catp.mauve ... }
#
# Previously a wallpaper-derived matugen palette filled this role —
# more reactive but visually disjoint from Ghostty / nvim (both on
# Catppuccin Mocha). Hardcoding the palette to match the terminal +
# editor keeps the entire desktop on one theme and removes the
# matugen IFD from every rebuild.

{
  _module.args.catp = {
    # Backgrounds, dark → light
    crust    = "#11111b";  # deepest — bar, full-screen overlays
    mantle   = "#181825";  # popup panel bodies (mako, wofi, swayosd, wlogout)
    base     = "#1e1e2e";  # canonical Mocha base (terminal-equivalent)
    surface0 = "#313244";  # chips, interactive elements within panels
    surface1 = "#45475a";  # borders, more-elevated inputs

    # Text, dim → bright
    overlay0 = "#6c7086";
    subtext0 = "#a6adc8";  # muted text
    text     = "#cdd6f4";  # default text

    # Accents
    mauve    = "#cba6f7";  # primary accent (focus, selection, active workspace)
    peach    = "#fab387";  # warning / battery low / tertiary highlight
    red      = "#f38ba8";  # error / battery critical / destructive hover
  };
}
