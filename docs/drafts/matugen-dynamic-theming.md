# Wallpaper-derived theming — design note

Status: **draft / not started.** Deferred out of the 2026-05-14 Hyprland
cherry-pick pass (hypridle/hyprlock/swayosd/cliphist landed; this did not).
Updated 2026-05-14 with web research — see Sources at the end.

## What we're deciding

The reference config (`~/Code/references/nixos-configuration`,
ilyamiro's imperative-dots) looks "cool" because of two things working
together: a **Material You** palette extracted from the wallpaper, and
**live re-theming** — change the wallpaper, the whole desktop re-tints
without a rebuild. Today this repo has a *static* hand-tuned Nord-ish
palette spread across `desktop-shell.nix` (waybar + mako), `theming.nix`
(GTK), `hyprland.nix` / `desktop-shell.nix` (hyprlock), and the Ghostty
themes in `default.nix`.

There is a genuine values tension here, and it's the whole decision:

- **Reproducible + typed** (the repo's stated philosophy) wants the
  palette to be a *build input* — wallpaper changes mean a rebuild.
- **Live + dynamic** (what makes the reference cool) wants the palette
  to be *runtime state* — which the read-only store can't hold, so it
  becomes a deliberate mutable-state carve-out, like `~/.claude.json`.

You can't have both fully. The three options below sit at different
points on that line.

## Option 1 — Stylix (declarative, base16, whole-desktop)

[Stylix](https://github.com/nix-community/stylix) is the idiomatic NixOS
theming framework. Add `stylix.nixosModules.stylix` to the host (it
auto-wires the home-manager side when HM is a NixOS module — confirmed
for our setup), point `stylix.image` at a wallpaper, and it generates a
**base16** scheme via a genetic algorithm at build time and themes
~27+ apps — including every app in our stack: waybar, mako, hyprlock,
hyprland, ghostty, GTK, Qt, fonts, cursors. Per-target opt-out via
`stylix.targets.<name>.enable`; `stylix.autoEnable = false` flips to
opt-in.

- **Fit with repo philosophy:** excellent. It *is* a typed module, writes
  theme config into the store like every other HM module, no
  out-of-store symlinks, no mutable state.
- **Cost:** it's **base16, not Material You** — Material You is only a
  planning-stage tracking issue ([#2031](https://github.com/nix-community/stylix/issues/2031),
  no PRs merged). And it's **purely build-time** — wallpaper change ⇒
  rebuild; the only "fast" path is HM specialisations toggling between
  pre-built themes ([#530](https://github.com/nix-community/stylix/issues/530)).
  Adopting it also means handing the whole palette to a framework and
  retiring the hand-tuned Nord look.
- **Verdict:** the low-effort, high-coverage, philosophically-clean
  option — but it delivers *neither* of the two things that made the
  reference cool. Pick it only if "consistent theming everywhere,
  declaratively" matters more than Material You or live switching.

## Option 2 — matugen, build-time (declarative, Material You, typed)

matugen's flake ships a module exposing `programs.matugen`
([module.nix](https://github.com/InioX/matugen/blob/main/module.nix)).
It runs matugen *inside a derivation at build time* from a fixed
`wallpaper` (or `source_color`) and exposes two read-only outputs:

- `config.programs.matugen.theme.colors` — the palette parsed into a
  native Nix attrset (via IFD — `builtins.fromJSON` on the built
  derivation). Shape (matugen v4): `colors.<role>.{dark,light,default}.color`,
  where `<role>` is the M3 set (`primary`, `on_primary`, `surface`, …).
- `config.programs.matugen.theme.files` — a derivation of rendered
  template outputs.

The move: feed `theme.colors` into the **existing typed modules** —
`programs.waybar.style`, `services.mako.settings`,
`programs.hyprlock.settings`, `theming.nix`, Ghostty themes. This is
exactly the pattern in
[SegmentationViolator/hm-config](https://github.com/SegmentationViolator/hm-config)
(closest match to our stack: HM-as-NixOS-module, feeds `theme.colors`
into `services.mako.settings` and `theme.files` into `programs.waybar.style`).

- **Fit with repo philosophy:** good. Stays typed, stays reproducible,
  no mutable carve-out, no new daemons, no scripts. Fully reversible.
- **Cost:** still build-time — wallpaper change ⇒ rebuild. Adds an **IFD**
  (eval now builds the matugen derivation). And you wire each app's
  colours yourself — there's no `theme.colors` → waybar magic.
- **Verdict:** delivers the Material You *look* without giving up the
  repo's principles. The realistic first step — and Option 3 can be
  layered on later reusing the same templates.

## Option 3 — matugen, runtime (live switching, mutable carve-out)

The `programs.matugen` *module* cannot do this — it's frozen at build
time. Live switching means the matugen **CLI** against a mutable
`~/.config/matugen/config.toml`: a keybind/picker runs `matugen image
<path>`, which sets the wallpaper, renders templates to mutable paths,
and fires per-template `post_hook`s that reload each app.

The split that makes it tolerable: structural config stays typed in Nix
but each app `@import`/`source`/`config-file`s a **fixed mutable path**
matugen owns and Nix never writes:

- waybar `style.css`: `@import "colors.css";` + `pkill -SIGUSR2 waybar`
- mako: generated colour include + `makoctl reload`
- hyprland: `source = ~/.config/hypr/colors.conf` + `hyprctl reload`
- hyprlock: re-reads on next lock — free, nothing to signal
- ghostty: `config-file = ~/.config/ghostty/colors` + `pkill -SIGUSR2
  ghostty` (SIGUSR2 **only** — other signals crash Ghostty)

- **Fit with repo philosophy:** this is the invasive one. Generated
  `colors.*` files are runtime-mutable state, gitignored, not
  nix-managed — a deliberate carve-out, same rule as `~/.claude.json`.
  The picker script *should* still be typed (`writeShellApplication`).
- **Costs / sharp edges:**
  - **GTK/Qt are the weak link** — no clean live-reload signal; real
    configs restart GTK apps or use a gsettings-toggle hack. GTK4 is
    better than GTK3, neither is clean.
  - matugen [bug #127](https://github.com/InioX/matugen/issues/127):
    signal-sending `post_hook`s race; mitigate with async (`&`) and the
    per-template `index` field.
  - No public repo does "NixOS + Hyprland + matugen + typed modules +
    live retheme" cleanly — NixOS configs found either keep themed
    dotfiles as loose non-Nix files (Sincide/nixos-config) or theme
    statically (Frost-Phoenix). Our intended design is novel synthesis.
- **Verdict:** the actual "cool" experience, at the cost of a standing
  mutable-state mechanism beside the typed modules. Best treated as a
  *later* layer on top of Option 2, not the starting point.

## Cross-cutting facts that constrain all three

- **swww was renamed to `awww`** (Oct 2025, moved to Codeberg, GitHub
  repo archived). home-manager 25.11 ships `services.awww`
  (`services.swww` aliased to it). A runtime wallpaper-switching flow
  wants `awww` — transitions, one-command runtime switch, no preload
  bookkeeping. `hyprpaper` (current) is fine for a *static* or
  rebuild-time wallpaper but has no transitions and keeps every
  preloaded image in RAM. Options 1–2 can keep hyprpaper; Option 3
  wants `awww`.
- **matugen versioning:** nixpkgs 25.11 ships matugen **3.0.0** — two
  majors behind upstream **4.1.0**. v4.0.0 was a breaking release that
  changed the `--json` output shape. The flake's module assumes v4. If
  we adopt matugen, use the **flake input pinned to `v4.1.0`** (not the
  nixpkgs package) so module and binary stay in lockstep — and design
  `theme.colors` consumers around the v4 `colors.<role>.<scheme>.color`
  shape.
- **matugen's old `reload_apps` / `reload_apps_list` is gone** — current
  matugen reloads via per-template `post_hook` only.
- **Wallpaper choice matters:** Material You / base16 extraction both
  produce muted palettes from muted images. Our current wallpaper
  (`nixos-artwork … simple-dark-gray`) would give a flat result — a
  more colourful wallpaper is part of the cost of entry.

## Decision matrix

| | Stylix | matugen build-time | matugen runtime |
|---|---|---|---|
| Palette style | base16 | Material You | Material You |
| Live wallpaper switch | no (rebuild) | no (rebuild) | **yes** |
| Stays fully typed/declarative | **yes** | **yes** | partial (mutable carve-out) |
| App coverage | broad, automatic | what you wire | what you template |
| New machinery | flake input | flake input + IFD | + awww, scripts, mutable files, hooks |
| Effort | low | medium | high |
| Reversible | yes | yes | yes, but more to unwind |
| Delivers the "cool" factor | neither | the *look* | look **and** feel |

## Recommendation

**The end goal (build-time / runtime / Stylix) is deliberately deferred.**
It can't be answered in the abstract — it depends on whether matugen's
extracted palette actually looks good on this hardware. So the plan is a
**decision-independent spike first**: wire `programs.matugen` →
`theme.colors` into *one* surface (hyprlock), `nix flake check`, look at
it. That first step is identical regardless of which of the three
options we eventually pick; the build-time-vs-runtime fork only matters
at the full rollout. Decide the end goal *after* seeing the spike.

Start with **Option 2 (matugen build-time)** for that spike: it
delivers the Material You look that made the reference appealing, stays
inside the repo's typed-modules + reproducible philosophy, adds no
mutable state or daemons, and is fully reversible. The one real cost is
the IFD on eval.

Treat **Option 3 (runtime)** as a *separate, later* decision — it reuses
Option 2's templates, so nothing is wasted, and we'd only take it on if
rebuild-to-restyle proves genuinely annoying in practice. It is a real
architecture change (mutable carve-out + `awww` + picker + hooks), not a
feature toggle.

**Option 1 (Stylix)** stays on the table as the "actually, minimal
effort and I'd accept base16" escape hatch — but it's a different
product (whole-desktop framework, no Material You, no live switch), so
choosing it is choosing a different goal, not a cheaper version of this
one.

Either way: own focused commit series, not folded into an unrelated pass.

## If we go Option 2 — concrete starting steps

1. Add the matugen flake input, pinned `ref = "refs/tags/v4.1.0"`,
   `inputs.nixpkgs.follows`.
2. Import `matugen.nixosModules.default` into the HM config; set
   `programs.matugen = { enable = true; wallpaper = <colourful pinned
   image>; type = "scheme-tonal-spot"; jsonFormat = "hex"; }`.
3. Replace the hard-coded Nord hexes in `desktop-shell.nix`
   (`programs.waybar.style`, `services.mako.settings`,
   `programs.hyprlock.settings`) and `theming.nix` with references into
   `config.programs.matugen.theme.colors`.
4. Decide hyprpaper stays (it does, for build-time) and that the
   matugen `wallpaper` and the hyprpaper wallpaper are the *same* pinned
   image — single source of truth.
5. `nix flake check` will now do an IFD build — confirm eval time is
   acceptable.

## Open questions

- Which apps must re-tint? waybar + mako + hyprlock + Ghostty + GTK is
  the real want; the reference also does discord/firefox/nvim — likely
  cruft for us.
- Pick the pinned wallpaper — needs to be colourful enough to give a
  palette worth having.
- Option 3 only: is the GTK/Qt weak link acceptable, or do we scope
  live re-theming to waybar/mako/hyprland/hyprlock and leave GTK static?

## Sources

- matugen: <https://github.com/InioX/matugen> · module.nix
  <https://github.com/InioX/matugen/blob/main/module.nix> · example
  config <https://github.com/InioX/matugen/blob/main/example/config.toml>
  · hook race bug <https://github.com/InioX/matugen/issues/127>
- matugen in nixpkgs 25.11 (3.0.0):
  <https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/by-name/ma/matugen/package.nix>
- Stylix: <https://github.com/nix-community/stylix> · docs
  <https://nix-community.github.io/stylix/> · Material You tracking
  issue <https://github.com/nix-community/stylix/issues/2031> · live
  theme issue <https://github.com/nix-community/stylix/issues/530>
- swww→awww rename: <https://codeberg.org/LGFae/awww> ·
  <https://www.lgfae.com/posts/2025-10-29-RenamingSwww.html> ·
  `services.awww` <https://github.com/nix-community/home-manager/blob/master/modules/services/awww.nix>
- Real configs — build-time:
  <https://github.com/SegmentationViolator/hm-config> ·
  <https://github.com/localcc/nixos-config>
- Real configs — runtime / pipeline mechanics:
  <https://github.com/binnewbs/arch-hyprland> ·
  <https://github.com/Sincide/nixos-config> ·
  <https://github.com/Frost-Phoenix/nixos-config>
- Other theming tools: nix-colors
  <https://github.com/Misterio77/nix-colors> · wallust
  <https://codeberg.org/explosion-mental/wallust>
