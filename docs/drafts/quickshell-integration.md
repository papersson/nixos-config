# Quickshell integration — design draft

Status: **not started** — design notes only. Captures how a Quickshell-based
desktop shell *would* slot into this flake, and why the obvious approach (port
someone's dotfiles) is the wrong one.

## Context

Question that prompted this: "what's the proper and elegant way to run
Quickshell on NixOS?" — triggered by looking at `ilyamiro/imperative-dots`
(vendored at `~/Code/references/nixos-configuration`), whose README says
outright "Do NOT install it on NixOS."

Quickshell is a QtQuick/QML *toolkit* for building Wayland desktop shells —
bars, widgets, popups, lockscreens, launchers. It is not a shell itself; you
point it at a QML config tree and it renders it. On this machine it would
*replace* the current waybar + mako + hyprpaper (+ optionally hyprlock,
swayosd) stack with one programmable surface, with Hyprland left as-is.

## Key finding: it's already in our pins

No flake input gymnastics needed.

- `pkgs.quickshell` — present in pinned nixpkgs 25.11, version `0.2.1`.
- `programs.quickshell` — present as a **typed home-manager module** in pinned
  home-manager release-25.11. Options: `enable`, `package`, `configs`,
  `activeConfig`, `systemd`.

So this satisfies the repo's "typed module over config-file drop" rule
natively. nixpkgs lags upstream Quickshell; if `0.2.1` proves too old, the
fallback is adding the upstream flake as an input — but start with the pin.

## The principle: separate three things

The reason invasive configs (ilyamiro's) fail on NixOS is they conflate three
concerns that must stay separate:

| Concern | Belongs in |
|---|---|
| The `quickshell` binary **+ the ~28 tools its QML shells out to** (`hyprctl`, `nmcli`, `wpctl`, `jq`, `playerctl`, `imagemagick`, `cliphist`, `brightnessctl`, `libnotify`…) | Nix — **wrapped**, so the closure is on the shell's own PATH, not scattered into `home.packages` |
| The QML / script source tree | `/nix/store`, read-only, via `programs.quickshell.configs` |
| Runtime state — caches, the SQLite focus DB, any `settings.json` the shell *rewrites itself* | `~/.cache`, `~/.local/state`, `$XDG_RUNTIME_DIR` — **not** nix-managed. Correct, not a hack: same carve-out as `~/.claude.json`. |

ilyamiro's specific mistake: it writes its mutable `settings.json` *inside* the
config tree (`~/.config/hypr/settings.json`), tangling immutable and mutable so
neither half can be managed cleanly. Its tree also assumes a writable
`~/.config`, rewrites wallpapers in place, and spawns Python daemons — wrong
shape for the read-only store regardless of wrapping.

## Concrete shape (if/when implemented)

In `home/patrikpersson/desktop-shell.nix`:

```nix
programs.quickshell = {
  enable = true;
  package = quickshellWrapped;     # binary + tool closure
  configs.t14 = ./quickshell;      # QML tree → shipped to the store
  activeConfig = "t14";
  systemd.enable = true;           # user service — same model as waybar today
};
```

Wrapping the closure so the QML's `Process` calls resolve:

```nix
quickshellWrapped = pkgs.symlinkJoin {
  name = "quickshell-wrapped";
  paths = [ pkgs.quickshell ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/quickshell --prefix PATH : ${lib.makeBinPath [
      hyprland jq playerctl networkmanager wireplumber
      bluez imagemagick cliphist libnotify brightnessctl
    ]}
  '';
};
```

This matches the existing architecture: all current shell daemons (waybar,
mako, hyprpaper, hypridle, swayosd, cliphist) are systemd user services defined
in `desktop-shell.nix`; `systemd.enable = true` keeps Quickshell consistent
with that.

### Hot-reload tradeoff

Quickshell's signature DX is live-editing QML with instant reload. From the
store that's gone — rebuild per change. Two resolutions:

- **Dev:** point `configs.t14` at a `mkOutOfStoreSymlink` of the working-tree
  dir → live edit, no rebuild. Switch back to the pure `./quickshell` path once
  stable.
- **Or:** just accept rebuild-per-tweak, as we already do for
  `~/.claude/settings.json`.

## Decision point: pre-built shell vs. own QML

Quickshell replaces the *entire* current shell stack — a big swap. Two proper
paths:

1. **Adopt a pre-built shell that ships its own Nix flake** —
   DankMaterialShell, Noctalia, Caelestia all provide flakes / HM modules that
   already solve the closure + state separation. Add one flake input,
   `programs.<shell>.enable = true`. Lowest effort, still fully declarative.
2. **Write our own small QML config**, packaged as above — start with *just a
   bar*, do not grow a 61-file tree.

Not an option: porting ilyamiro's tree (61 QML files, 32 shell scripts, 4
Python daemons, mutable-`~/.config` assumption).

## Interaction with matugen draft

See `matugen-dynamic-theming.md`. `MatugenColors.qml` in real-world configs
polls a colors JSON at runtime (e.g. `/tmp/qs_colors.json`) — that is exactly
the "shape B" runtime re-theming the matugen draft describes. Quickshell is a
more natural host for dynamic theming than waybar's static CSS. If dynamic
theming is the real goal, these two drafts should be picked up together.

## Open questions

- Pre-built shell or own QML? (governs everything downstream)
- Is `pkgs.quickshell` 0.2.1 recent enough, or is the upstream flake input
  needed?
- How much of the current stack to actually replace — bar only, or also
  notifications / lockscreen / launcher?
- Is this even wanted, given the current typed stack works cleanly? This may
  stay a draft indefinitely.
