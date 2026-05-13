# handover-nvim.md

Replace the current ad-hoc LazyVim deployment with a fully declarative
Neovim configuration via `programs.nixvim`. The existing setup works
but carries three pieces of technical debt this handover exists to
eliminate.

## Context

- Repo root: `/etc/nixos`. Flake-based NixOS 25.11. Single host `t14`,
  single user `patrikpersson`. Read `CLAUDE.md`, `handover.md`, and
  `home/patrikpersson/default.nix` before starting.
- Rebuilds: `nh os switch` (preferred) — needs sudo, must be handed
  off to the human, not invoked from a tool.
- Workflow: edit → `git add` → `nix flake check` → commit → rebuild.
  New files must be `git add`-ed before they're visible to the flake
  evaluator.
- The HM module is wired as a NixOS module (`home-manager.users.patrikpersson`),
  not standalone.

## Why this exists

The current `home/patrikpersson/nvim/` deployment was a fast
translation of `~/dotfiles/base/nvim/` (LazyVim distro) into the
flake. It works but has three concrete problems:

1. **Mason fails silently.** LazyVim defaults pull in
   `mason.nvim` + `mason-lspconfig`, which download LSP binaries to
   `~/.local/share/nvim/mason/`. Those binaries are dynamically linked
   against `/lib64/ld-linux-x86-64.so.2`, which doesn't exist on
   NixOS. The user perceives "LSPs don't work" with no clear error.
2. **Config is duplicated.** `~/dotfiles/base/nvim/` (Mac source of
   truth) and `home/patrikpersson/nvim/` (NixOS source of truth) will
   drift. No reconciliation mechanism.
3. **Read-only writebacks.** `~/.config/nvim/` is a tree of
   nix-store symlinks. `lazy.nvim` trying to write `lazy-lock.json`
   and LazyVim trying to update `lazyvim.json` (dismissed news) both
   fail. Surfaces as warnings on every `:Lazy sync`.

`programs.nixvim` solves all three: plugins as Nix derivations,
LSPs as proper Nix packages (no Mason), no runtime writeback paths
because there's no Lua config to mutate.

## Target state

- `nixvim` is a flake input.
- `programs.nixvim` is a fully-configured Neovim with the same
  plugins and keymaps the human currently uses from the Lua config.
- A documented set of LSPs is installed declaratively.
- No `home/patrikpersson/nvim/` directory in the repo.
- No `neovim` or `gcc` (added for treesitter compiles) in
  `home.packages`.
- No `xdg.configFile."nvim"` block.

## Source of truth for the translation

The Lua files at `home/patrikpersson/nvim/` are the spec. Read every
file under `lua/config/` and `lua/plugins/` and reproduce the
equivalent behavior in nixvim options. The plugin list is small:

| Lua file | Plugin | nixvim option (verify exact path) |
|---|---|---|
| `lua/plugins/colorscheme.lua` | `ellisonleao/gruvbox.nvim` with custom Treesitter + NeoTree highlight overrides | `colorschemes.gruvbox` (+ `highlightOverride` or `extraConfigLua` for the `["@function"]` style overrides) |
| `lua/plugins/flash.lua` | `folke/flash.nvim` | `plugins.flash` |
| `lua/plugins/git.lua` | `tpope/vim-fugitive` | `plugins.fugitive` |
| `lua/plugins/mini.lua` | `nvim-mini/mini.surround` | `plugins.mini` with `modules.surround` |
| `lua/plugins/neo-tree.lua` | `nvim-neo-tree/neo-tree.nvim` | `plugins.neo-tree` |
| `lua/plugins/telescope.lua` | `nvim-telescope/telescope.nvim` + `telescope-fzf-native.nvim` | `plugins.telescope` with `extensions.fzf-native` |

LazyVim core defaults to also reproduce (LazyVim auto-enables these;
make them explicit in nixvim):

- `plugins.cmp` — completion (nvim-cmp + sources)
- `plugins.lsp` (or `plugins.lspconfig`) — LSP client
- `plugins.treesitter` — syntax + textobjects (enable a parser set
  matching the user's language mix; see "LSP set" below)
- `plugins.conform` — formatter dispatch
- `plugins.lint` (`nvim-lint`) — linter dispatch
- `plugins.which-key` — keybind discoverability
- `plugins.gitsigns` — gutter git signs
- `plugins.lualine` — statusline
- `plugins.bufferline` — bufferline

Skip Mason and `mason-lspconfig` entirely. We're managing LSPs
declaratively.

### Options to set in `globals` / `opts`

From `lua/config/options.lua` — straight transcription, no judgment
calls needed. Notable: `tabstop = shiftwidth = softtabstop = 4`,
`expandtab`, `number`, `relativenumber`, `ignorecase` + `smartcase`,
`termguicolors`, `signcolumn = "yes"`, `scrolloff = 8`,
`clipboard = "unnamedplus"`, `undofile`, `splitbelow`, `splitright`.

Leader keys from `lua/config/lazy.lua`: `mapleader = " "`,
`maplocalleader = " "`.

### Keymaps

Reproduce every map in `lua/config/keymaps.lua`. They split into
groups; preserve the `<leader>` prefixes and `desc` strings exactly
so which-key keeps working. Note `jj` → `<Esc>` in insert mode is a
hard requirement (muscle memory).

### Autocmds

One autocmd in `lua/config/autocmds.lua`: markdown files get
`wrap = true`, `linebreak = true`. Trivial to port via
`autoCmd` list.

### LazyVim extras

`lazyvim.json` lists `lazyvim.plugins.extras.lang.zig`. The user
edits Zig. Install `zls` as the Zig LSP.

## LSP set (declarative, replaces Mason)

Start with this baseline — adjust if the user pushes back during
review:

- `nil` (or `nixd`, pick one — `nixd` is more accurate, `nil` is
  lighter) for Nix files
- `lua-language-server` — required for editing this config
- `bash-language-server` — shell scripts in the repo
- `pyright` — Python is in the user's stack
- `rust-analyzer` — Rust is in the user's stack
- `zls` — Zig (per lazyvim.json extras)
- `typescript-language-server` — TS/JS, common

Wire each via `programs.nixvim.plugins.lsp.servers.<name>.enable = true;`.
Nixvim handles installing the binary into the closure.

Skip TypeScript/Pyright if the user prefers lighter setups; ask
during PR.

## Migration plan

1. **Read this handover, then read `home/patrikpersson/nvim/`
   in full**: every `.lua` file, plus `lazyvim.json` and
   `stylua.toml`. Do NOT skim the keymap file; there are ~30
   distinct mappings.

2. **Add `nixvim` as a flake input.** Pattern:
   ```nix
   nixvim = {
     url = "github:nix-community/nixvim/nixos-25.11";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```
   Destructure it in the outputs signature alongside `sops-nix`,
   `lanzaboote`, etc.

3. **Wire the HM module.** Add `nixvim.homeManagerModules.nixvim`
   to `home-manager.sharedModules` in `flake.nix` (this is the same
   list where `sops-nix.homeManagerModules.sops` already lives).

4. **Build the `programs.nixvim` block** in
   `home/patrikpersson/default.nix`. Group the configuration into
   sub-attrs that mirror the source files: `globals`, `opts`,
   `keymaps`, `autoCmd`, `colorschemes`, `plugins`. The result is
   ~300–400 lines of Nix; keep it readable, comment any non-obvious
   translation.

5. **`nix flake check`** must pass before rebuild. Eval errors
   should surface from nixvim's option types (e.g.
   `plugins.telescope.settings.defaults.layout_config` expects an
   attrset, not a Lua table — translate accordingly).

6. **Hand off rebuild** to the human: `nh os switch`.

7. **Verify** (see checklist below). Iterate if anything's broken.

8. **Once verified working**, delete the hacky setup in one commit:
   - `rm -rf home/patrikpersson/nvim/`
   - From `home/patrikpersson/default.nix`:
     - Remove `neovim` from `home.packages`
     - Remove `gcc` from `home.packages` (treesitter under nixvim
       ships parsers pre-built; gcc isn't needed unless another
       package required it — verify nothing else depends on it first)
     - Remove the `xdg.configFile."nvim"` block and its preceding
       comment block
   - Update any references in `handover.md` (§2 Layout — drop the
     `nvim/` entry; §6 — add a Step N "Declarative Neovim via
     nixvim" entry marking this work done)

   Do this as a separate commit from the nixvim addition, so the
   diff is reviewable as "added nixvim" then "removed legacy
   deployment."

## Verification checklist

Run after rebuild. Each must pass before the cleanup commit.

- [ ] `nvim` launches without error and without an interactive
      "Mason needs to install X" prompt.
- [ ] `<leader>ff` opens Telescope find_files, lists files using
      ripgrep, fuzzy filter works.
- [ ] `<leader>e` toggles neo-tree.
- [ ] `s` triggers flash.nvim's labeled jump.
- [ ] `<C-h>/<C-j>/<C-k>/<C-l>` navigate windows.
- [ ] `jj` in insert mode escapes.
- [ ] Open a `.nix` file in this repo → LSP attaches (nixd or nil),
      hover (`K`) works, diagnostics appear on a deliberately broken
      line.
- [ ] Open a `.lua` file → lua-language-server attaches.
- [ ] `:Lazy` command **should not exist** (LazyVim is gone).
- [ ] `:Mason` command **should not exist** (Mason is gone).
- [ ] `gruvbox` colorscheme is active; the custom `@function`,
      `@type`, etc. highlight overrides from
      `lua/plugins/colorscheme.lua` are visible.
- [ ] `:checkhealth` reports no critical errors (warnings about
      optional providers like Perl/Ruby are fine).
- [ ] `which-key` popup appears when leader key is held.
- [ ] `:lua print(vim.fn.stdpath("config"))` reports the nixvim
      runtime config path (not `~/.config/nvim` — nixvim doesn't
      use it).

## Known traps

- **Nixvim option names diverge from upstream plugin names.** For
  example `telescope-fzf-native.nvim` is enabled via
  `plugins.telescope.extensions.fzf-native.enable`, not as a
  separate plugin. Look up each plugin's nixvim docs:
  <https://nix-community.github.io/nixvim/>.
- **Some Lua config doesn't translate to typed options.** Drop into
  `extraConfigLua` for things like the gruvbox `overrides` attrset
  if there's no typed option — but prefer typed where it exists,
  even at a small verbosity cost.
- **`globals` vs `opts`**: `vim.g.X` → `globals.X`,
  `vim.opt.X` → `opts.X`. Easy to confuse.
- **Keymaps use a list, not a function call**: `keymaps = [{ mode
  = "i"; key = "jj"; action = "<Esc>"; options.silent = true; }]`.

## Out of scope

- Adding LazyVim back as a wrapper. Don't.
- Symlinking `~/dotfiles/base/nvim/` for any reason. The user has
  decided that source-of-truth tension stays unresolved on the
  Mac side; we don't drag it back in.
- Migrating other dotfile content (tmux, helix, readline,
  ripgrep). Out of scope for this handover; see main `handover.md`
  §5 for the broader dotfiles question.
- Adding `programs.nix-ld`. Not needed without Mason.

## Done means

- `programs.nixvim` is the only Neovim deployment mechanism in the
  flake.
- `home/patrikpersson/nvim/` is gone from git history's tip.
- `home.packages` no longer mentions `neovim` or `gcc` (unless gcc
  is justified for some other reason).
- The verification checklist passes.
- `handover.md` reflects the new state.
