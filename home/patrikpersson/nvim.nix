{ pkgs, ... }:

# Declarative Neovim via programs.nixvim. Replaces the prior LazyVim-from-Lua
# deployment that lived under ./nvim/ — plugins are Nix derivations, LSP
# binaries come from nixpkgs (no Mason, no /lib64/ld-linux pain), and there
# are no runtime writeback paths because there's no on-disk Lua config.
#
# Layout below mirrors the source files that used to live in ./nvim/lua/:
#   globals + opts   ← lua/config/options.lua + lua/config/lazy.lua leaders
#   colorschemes     ← lua/plugins/colorscheme.lua
#   autoCmd          ← lua/config/autocmds.lua
#   keymaps          ← lua/config/keymaps.lua  + per-plugin map blocks
#   plugins          ← lua/plugins/*.lua  + LazyVim's auto-enabled defaults

{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # vim.g.X
    globals = {
      mapleader = " ";
      maplocalleader = " ";
    };

    # vim.opt.X — straight transcription of lua/config/options.lua
    opts = {
      tabstop = 4;
      shiftwidth = 4;
      softtabstop = 4;
      expandtab = true;

      number = true;
      relativenumber = true;

      ignorecase = true;
      smartcase = true;
      hlsearch = true;
      incsearch = true;

      termguicolors = true;
      signcolumn = "yes";
      wrap = false;
      scrolloff = 8;
      sidescrolloff = 8;
      cursorline = true;

      mouse = "a";
      clipboard = "unnamedplus";
      undofile = true;
      undolevels = 10000;
      updatetime = 250;
      timeoutlen = 300;
      splitbelow = true;
      splitright = true;

      completeopt = [ "menu" "menuone" "noselect" ];
    };

    colorschemes.gruvbox = {
      enable = true;
      settings = {
        transparent_mode = true;
        contrast = "soft";
        dim_inactive = true;
        italic = {
          strings = false;
          emphasis = false;
          comments = false;
          operators = false;
          folds = false;
        };
      };
    };

    # gruvbox.nvim's `overrides` table isn't exposed as a typed nixvim option,
    # so the NeoTree + Treesitter colour overrides from
    # lua/plugins/colorscheme.lua are applied via a ColorScheme autocmd.
    extraConfigLua = ''
      local function apply_gruvbox_overrides()
        local hl = {
          NeoTreeNormal = { bg = "NONE", fg = "#ebdbb2" },
          NeoTreeNormalNC = { bg = "NONE", fg = "#ebdbb2" },
          NeoTreeCursorLine = { bg = "#3c3836" },

          ["@function"] = { fg = "#b8bb26" },
          ["@function.call"] = { fg = "#b8bb26" },
          ["@variable"] = { fg = "#ebdbb2" },
          ["@field"] = { fg = "#83a598" },
          ["@parameter"] = { fg = "#fbf1c7" },
          ["@keyword"] = { fg = "#fb4934" },
          ["@keyword.function"] = { fg = "#fb4934" },
          ["@property"] = { fg = "#83a598" },
          ["@type"] = { fg = "#fabd2f" },
          ["@constructor"] = { fg = "#fabd2f" },
          ["@constant"] = { fg = "#d3869b" },
          ["@string"] = { fg = "#b8bb26" },
          ["@number"] = { fg = "#d3869b" },
          ["@boolean"] = { fg = "#d3869b" },
          ["@operator"] = { fg = "#ebdbb2" },
          ["@punctuation.delimiter"] = { fg = "#ebdbb2" },
          ["@punctuation.bracket"] = { fg = "#ebdbb2" },
          ["@comment"] = { fg = "#928374" },
          ["@namespace"] = { fg = "#83a598" },
        }
        for group, opts in pairs(hl) do
          vim.api.nvim_set_hl(0, group, opts)
        end
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "gruvbox",
        callback = apply_gruvbox_overrides,
      })
      apply_gruvbox_overrides()
    '';

    autoCmd = [
      {
        event = [ "FileType" ];
        pattern = [ "markdown" ];
        command = "setlocal wrap linebreak";
      }
    ];

    # Top-level keymaps from lua/config/keymaps.lua plus the simple
    # `<cmd>...<cr>` maps from the neo-tree and fugitive plugin specs.
    # Plugin-internal Lua function maps (flash) live in the plugins block.
    keymaps = [
      # Quick escape
      { mode = "i"; key = "jj"; action = "<Esc>"; options = { silent = true; noremap = true; }; }

      # Window navigation
      { mode = "n"; key = "<C-h>"; action = "<C-w>h"; options.desc = "Go to left window"; }
      { mode = "n"; key = "<C-j>"; action = "<C-w>j"; options.desc = "Go to lower window"; }
      { mode = "n"; key = "<C-k>"; action = "<C-w>k"; options.desc = "Go to upper window"; }
      { mode = "n"; key = "<C-l>"; action = "<C-w>l"; options.desc = "Go to right window"; }

      # Buffer navigation
      { mode = "n"; key = "[b"; action = "<cmd>bprevious<cr>"; options.desc = "Previous buffer"; }
      { mode = "n"; key = "]b"; action = "<cmd>bnext<cr>"; options.desc = "Next buffer"; }
      { mode = "n"; key = "<leader>bd"; action = "<cmd>bd<cr>"; options.desc = "Delete buffer"; }
      { mode = "n"; key = "<leader>bD"; action = "<cmd>bd!<cr>"; options.desc = "Force delete buffer"; }

      # Quickfix navigation
      { mode = "n"; key = "[q"; action = "<cmd>cprev<cr>"; options.desc = "Previous quickfix"; }
      { mode = "n"; key = "]q"; action = "<cmd>cnext<cr>"; options.desc = "Next quickfix"; }
      { mode = "n"; key = "<leader>co"; action = "<cmd>copen<cr>"; options.desc = "Open quickfix"; }
      { mode = "n"; key = "<leader>cc"; action = "<cmd>cclose<cr>"; options.desc = "Close quickfix"; }

      # Location list navigation
      { mode = "n"; key = "[l"; action = "<cmd>lprev<cr>"; options.desc = "Previous location"; }
      { mode = "n"; key = "]l"; action = "<cmd>lnext<cr>"; options.desc = "Next location"; }
      { mode = "n"; key = "<leader>lo"; action = "<cmd>lopen<cr>"; options.desc = "Open location list"; }
      { mode = "n"; key = "<leader>lc"; action = "<cmd>lclose<cr>"; options.desc = "Close location list"; }

      # Search and replace
      { mode = "n"; key = "<leader>rw"; action = ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>"; options.desc = "Replace word under cursor"; }
      { mode = "v"; key = "<leader>r"; action = ":s/"; options.desc = "Replace in selection"; }

      # Keep cursor centered when scrolling
      { mode = "n"; key = "<C-d>"; action = "<C-d>zz"; options.desc = "Scroll down"; }
      { mode = "n"; key = "<C-u>"; action = "<C-u>zz"; options.desc = "Scroll up"; }
      { mode = "n"; key = "n"; action = "nzzzv"; options.desc = "Next search result"; }
      { mode = "n"; key = "N"; action = "Nzzzv"; options.desc = "Previous search result"; }

      # Better indenting (stay in visual mode)
      { mode = "v"; key = "<"; action = "<gv"; options.desc = "Indent left"; }
      { mode = "v"; key = ">"; action = ">gv"; options.desc = "Indent right"; }

      # Move lines
      { mode = "n"; key = "<A-j>"; action = "<cmd>m .+1<cr>=="; options.desc = "Move line down"; }
      { mode = "n"; key = "<A-k>"; action = "<cmd>m .-2<cr>=="; options.desc = "Move line up"; }
      { mode = "v"; key = "<A-j>"; action = ":m '>+1<cr>gv=gv"; options.desc = "Move selection down"; }
      { mode = "v"; key = "<A-k>"; action = ":m '<-2<cr>gv=gv"; options.desc = "Move selection up"; }

      # Jump list
      { mode = "n"; key = "<leader>jo"; action = "<C-o>"; options.desc = "Jump back"; }
      { mode = "n"; key = "<leader>ji"; action = "<C-i>"; options.desc = "Jump forward"; }

      # Marks
      { mode = "n"; key = "<leader>ml"; action = "<cmd>marks<cr>"; options.desc = "List marks"; }
      { mode = "n"; key = "<leader>md"; action = "<cmd>delmarks a-z<cr>"; options.desc = "Delete all marks"; }

      # Tags (requires ctags)
      { mode = "n"; key = "<leader>tj"; action = "<C-]>"; options.desc = "Jump to tag"; }
      { mode = "n"; key = "<leader>tb"; action = "<C-t>"; options.desc = "Jump back from tag"; }
      { mode = "n"; key = "<leader>ts"; action = "g]"; options.desc = "List matching tags"; }

      # Macro helpers
      { mode = "n"; key = "Q"; action = "@q"; options.desc = "Play macro q"; }
      { mode = "v"; key = "Q"; action = ":norm @q<cr>"; options.desc = "Play macro q on selection"; }

      # Clear search highlighting
      { mode = "n"; key = "<leader>h"; action = "<cmd>nohlsearch<cr>"; options.desc = "Clear search highlight"; }

      # System clipboard
      { mode = [ "n" "v" ]; key = "<leader>y"; action = "\"+y"; options.desc = "Yank to clipboard"; }
      { mode = "n"; key = "<leader>Y"; action = "\"+Y"; options.desc = "Yank line to clipboard"; }
      { mode = [ "n" "v" ]; key = "<leader>p"; action = "\"+p"; options.desc = "Paste from clipboard"; }
      { mode = [ "n" "v" ]; key = "<leader>P"; action = "\"+P"; options.desc = "Paste before from clipboard"; }

      # Save / quit
      { mode = "n"; key = "<leader>w"; action = "<cmd>w<cr>"; options.desc = "Save file"; }
      { mode = "n"; key = "<leader>W"; action = "<cmd>wa<cr>"; options.desc = "Save all files"; }
      { mode = "n"; key = "<leader>q"; action = "<cmd>q<cr>"; options.desc = "Quit"; }
      { mode = "n"; key = "<leader>Q"; action = "<cmd>qa<cr>"; options.desc = "Quit all"; }

      # Split management
      { mode = "n"; key = "<leader>sv"; action = "<C-w>v"; options.desc = "Split vertical"; }
      { mode = "n"; key = "<leader>sh"; action = "<C-w>s"; options.desc = "Split horizontal"; }
      { mode = "n"; key = "<leader>se"; action = "<C-w>="; options.desc = "Equal splits"; }
      { mode = "n"; key = "<leader>sx"; action = "<cmd>close<cr>"; options.desc = "Close split"; }

      # Neo-tree (from lua/plugins/neo-tree.lua keys block)
      { mode = "n"; key = "<leader>e"; action = "<cmd>Neotree toggle<cr>"; options.desc = "Toggle Neo-tree"; }
      { mode = "n"; key = "<leader>E"; action = "<cmd>Neotree reveal<cr>"; options.desc = "Reveal file in Neo-tree"; }
      { mode = "n"; key = "-"; action = "<cmd>Neotree float<cr>"; options.desc = "Neo-tree float"; }

      # Fugitive (from lua/plugins/git.lua keys block)
      { mode = "n"; key = "<leader>gg"; action = "<cmd>Git<cr>"; options.desc = "Git status"; }
      { mode = "n"; key = "<leader>gb"; action = "<cmd>Git blame<cr>"; options.desc = "Git blame"; }
      { mode = "n"; key = "<leader>gd"; action = "<cmd>Gdiff<cr>"; options.desc = "Git diff"; }
      { mode = "n"; key = "<leader>gl"; action = "<cmd>Git log<cr>"; options.desc = "Git log"; }
      { mode = "n"; key = "<leader>gp"; action = "<cmd>Git push<cr>"; options.desc = "Git push"; }
      { mode = "n"; key = "<leader>gP"; action = "<cmd>Git pull<cr>"; options.desc = "Git pull"; }

      # Flash (was a `keys =` block on the plugin; uses Lua function calls,
      # so each action goes through __raw)
      { mode = [ "n" "x" "o" ]; key = "s"; action.__raw = "function() require('flash').jump() end"; options.desc = "Flash"; }
      { mode = [ "n" "x" "o" ]; key = "S"; action.__raw = "function() require('flash').treesitter() end"; options.desc = "Flash Treesitter"; }
      { mode = "o"; key = "r"; action.__raw = "function() require('flash').remote() end"; options.desc = "Remote Flash"; }
      { mode = [ "o" "x" ]; key = "R"; action.__raw = "function() require('flash').treesitter_search() end"; options.desc = "Treesitter Search"; }
      { mode = "c"; key = "<C-s>"; action.__raw = "function() require('flash').toggle() end"; options.desc = "Toggle Flash Search"; }
    ];

    plugins = {
      # ─── From lua/plugins/*.lua ──────────────────────────────────────────

      flash = {
        enable = true;
        settings = {
          labels = "asdfghjklqwertyuiopzxcvbnm";
          search = {
            mode = "exact";
            incremental = true;
          };
          jump = {
            jumplist = true;
            pos = "start";
            history = false;
            register = false;
            nohlsearch = false;
            autojump = false;
          };
          modes = {
            char = {
              enabled = true;
              autohide = false;
              jump_labels = true;
              multi_line = true;
              label = { exclude = "hjkliardc"; };
              # nixvim types this as attrset-or-raw, not list — pass raw Lua
              keys.__raw = ''{ "f", "F", "t", "T", ";", "," }'';
              search = { wrap = false; };
              highlight = { backdrop = true; };
              jump = { register = false; };
            };
            search = {
              enabled = true;
              highlight = { backdrop = false; };
              jump = { history = true; register = true; nohlsearch = true; };
              search = {
                forward = true;
                wrap = true;
                mode = "fuzzy";
                incremental = true;
              };
            };
            treesitter = {
              labels = "abcdefghijklmnopqrstuvwxyz";
              jump = { pos = "range"; };
              search = { incremental = false; };
              label = { before = true; after = true; style = "inline"; };
              highlight = {
                backdrop = false;
                matches = false;
              };
            };
          };
        };
      };

      fugitive.enable = true;

      mini = {
        enable = true;
        modules = {
          surround = {
            mappings = {
              add = "sa";
              delete = "sd";
              find = "sf";
              find_left = "sF";
              highlight = "sh";
              replace = "sr";
              update_n_lines = "sn";
            };
          };
        };
      };

      neo-tree = {
        enable = true;
        # As of nixvim 25.11 the typed top-level options on neo-tree are
        # gone — everything lives under `.settings.*` with the upstream
        # snake_case naming.
        settings = {
          close_if_last_window = true;
          popup_border_style = "rounded";
          enable_git_status = true;
          enable_diagnostics = true;
          sources = [ "filesystem" "buffers" "git_status" ];

          filesystem = {
            filtered_items = {
              hide_dotfiles = false;
              hide_gitignored = false;
              hide_by_name = [ "node_modules" ];
            };
            follow_current_file = {
              enabled = true;
              leave_dirs_open = false;
            };
            use_libuv_file_watcher = true;
          };

          window = {
            position = "left";
            width = 30;
            mappings = {
              "<space>" = "none";
              "<cr>" = "open";
              "l" = "open";
              "h" = "close_node";
              "<esc>" = "cancel";
              "S" = "open_split";
              "s" = "open_vsplit";
              "t" = "open_tabnew";
              "A" = "add_directory";
              "d" = "delete";
              "r" = "rename";
              "y" = "copy_to_clipboard";
              "x" = "cut_to_clipboard";
              "p" = "paste_from_clipboard";
              "c" = "copy";
              "m" = "move";
              "R" = "refresh";
              "?" = "show_help";
              "<" = "prev_source";
              ">" = "next_source";
            };
          };

          default_component_configs = {
            indent = {
              with_expanders = true;
              expander_collapsed = "";
              expander_expanded = "";
              expander_highlight = "NeoTreeExpander";
            };
            git_status = {
              symbols = {
                added = "";
                modified = "";
                deleted = "✖";
                renamed = "󰁕";
                untracked = "";
                ignored = "";
                unstaged = "󰄱";
                staged = "";
                conflict = "";
              };
            };
          };
        };
      };

      telescope = {
        enable = true;
        # fzf-native's settings (fuzzy, override_generic_sorter,
        # override_file_sorter, case_mode) are managed by the typed
        # extension module — defaults match the LazyVim spec, so just
        # enable and let nixvim wire it in.
        extensions.fzf-native.enable = true;

        # Picker keymaps from lua/plugins/telescope.lua `keys` block. Each
        # value is the picker name; nixvim wires `<cmd>Telescope <name><cr>`.
        keymaps = {
          "<leader>ff" = { action = "find_files"; options.desc = "Find files"; };
          "<leader>fg" = { action = "live_grep"; options.desc = "Live grep"; };
          "<leader>fb" = { action = "buffers"; options.desc = "Buffers"; };
          "<leader>fh" = { action = "help_tags"; options.desc = "Help tags"; };
          "<leader>fo" = { action = "oldfiles"; options.desc = "Recent files"; };
          "<leader>fw" = { action = "grep_string"; options.desc = "Grep word under cursor"; };
          "gr" = { action = "grep_string"; options.desc = "Grep references"; };
          "<leader>fm" = { action = "marks"; options.desc = "Marks"; };
          "<leader>fj" = { action = "jumplist"; options.desc = "Jump list"; };
          "<leader>fr" = { action = "registers"; options.desc = "Registers"; };
          "<leader>gc" = { action = "git_commits"; options.desc = "Git commits"; };
          "<leader>gs" = { action = "git_status"; options.desc = "Git status"; };
          "gd" = { action = "tags"; options.desc = "Go to definition (tags)"; };
          "<leader>ft" = { action = "tags"; options.desc = "Tags"; };
          "<leader>fT" = { action = "current_buffer_tags"; options.desc = "Buffer tags"; };
          "<leader>fc" = { action = "commands"; options.desc = "Commands"; };
          "<leader>fk" = { action = "keymaps"; options.desc = "Keymaps"; };
          "<leader>f:" = { action = "command_history"; options.desc = "Command history"; };
          "<leader>f/" = { action = "search_history"; options.desc = "Search history"; };
          "<leader>fq" = { action = "quickfix"; options.desc = "Quickfix list"; };
          "<leader>fl" = { action = "loclist"; options.desc = "Location list"; };
        };

        settings = {
          defaults = {
            mappings = {
              i = {
                "<C-j>".__raw = "require('telescope.actions').move_selection_next";
                "<C-k>".__raw = "require('telescope.actions').move_selection_previous";
                "<C-q>".__raw = "require('telescope.actions').send_selected_to_qflist + require('telescope.actions').open_qflist";
                "<M-q>".__raw = "require('telescope.actions').send_to_qflist + require('telescope.actions').open_qflist";
                "<C-x>".__raw = "require('telescope.actions').select_horizontal";
                "<C-v>".__raw = "require('telescope.actions').select_vertical";
                "<C-t>".__raw = "require('telescope.actions').select_tab";
                "<C-u>".__raw = "require('telescope.actions').preview_scrolling_up";
                "<C-d>".__raw = "require('telescope.actions').preview_scrolling_down";
              };
              n = {
                "q".__raw = "require('telescope.actions').close";
                "<C-q>".__raw = "require('telescope.actions').send_selected_to_qflist + require('telescope.actions').open_qflist";
              };
            };
            layout_config = {
              horizontal = {
                preview_width = 0.55;
                results_width = 0.8;
              };
              vertical = {
                mirror = false;
              };
              width = 0.87;
              height = 0.80;
            };
            path_display = [ "truncate" ];
            winblend = 0;
            borderchars = [ "─" "│" "─" "│" "╭" "╮" "╯" "╰" ];
            color_devicons = true;
          };
          pickers = {
            find_files = {
              find_command = [ "rg" "--files" "--hidden" "--glob" "!.git/*" ];
            };
            live_grep = {
              additional_args.__raw = ''function() return { "--hidden", "--glob", "!.git/*" } end'';
            };
            grep_string = {
              additional_args.__raw = ''function() return { "--hidden", "--glob", "!.git/*" } end'';
            };
          };
        };
      };

      web-devicons.enable = true;   # neo-tree dependency

      # ─── LazyVim auto-enabled defaults, made explicit ────────────────────

      treesitter = {
        enable = true;
        # Parsers come from nixpkgs (pre-built — no gcc needed at runtime).
        # Default `grammarPackages` pulls in *every* parser nvim-treesitter
        # knows about (~250 MB of closure for things like wgsl_bevy that
        # this user will never edit); curate to the active language mix.
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          bash
          c
          comment
          css
          diff
          dockerfile
          fish
          git_config
          git_rebase
          gitattributes
          gitcommit
          gitignore
          html
          javascript
          json
          jsonc
          lua
          luadoc
          luap
          markdown
          markdown_inline
          nix
          python
          query
          regex
          rust
          toml
          tsx
          typescript
          vim
          vimdoc
          yaml
          zig
        ];
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };

      treesitter-textobjects.enable = true;

      which-key.enable = true;
      gitsigns.enable = true;
      lualine.enable = true;
      bufferline.enable = true;

      # Completion
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          sources = [
            { name = "nvim_lsp"; }
            { name = "path"; }
            { name = "buffer"; }
            { name = "luasnip"; }
          ];
          mapping = {
            "<C-Space>".__raw = "cmp.mapping.complete()";
            "<CR>".__raw = "cmp.mapping.confirm({ select = true })";
            "<Tab>".__raw = ''
              cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                else
                  fallback()
                end
              end, { "i", "s" })
            '';
            "<S-Tab>".__raw = ''
              cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_prev_item()
                else
                  fallback()
                end
              end, { "i", "s" })
            '';
          };
        };
      };

      cmp-nvim-lsp.enable = true;
      cmp-buffer.enable = true;
      cmp-path.enable = true;
      luasnip.enable = true;
      cmp_luasnip.enable = true;

      # Formatter dispatch
      conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft = {
            nix = [ "nixfmt" ];
            lua = [ "stylua" ];
            python = [ "ruff_format" ];
            rust = [ "rustfmt" ];
            zig = [ "zigfmt" ];
            javascript = [ "prettier" ];
            typescript = [ "prettier" ];
          };
        };
      };

      # Linter dispatch — empty `linters_by_ft` is fine; user adds when needed
      lint = {
        enable = true;
        lintersByFt = { };
      };

      # ─── LSP (replaces Mason — binaries come from nixpkgs) ───────────────

      lsp = {
        enable = true;
        servers = {
          # Nix — `nil` is the lighter option (vs. `nixd`).
          nil_ls.enable = true;
          # Required for editing this config tree.
          lua_ls.enable = true;
          # Shell scripts in the repo.
          bashls.enable = true;
          # Python in the user's stack.
          pyright.enable = true;
          # Rust in the user's stack.
          rust_analyzer = {
            enable = true;
            installCargo = false;
            installRustc = false;
          };
          # Zig (per the old lazyvim.json extras lang.zig entry).
          zls.enable = true;
          # TypeScript/JavaScript — common.
          ts_ls.enable = true;
        };
        keymaps = {
          silent = true;
          lspBuf = {
            "K" = { action = "hover"; desc = "Hover"; };
            "gd" = { action = "definition"; desc = "Go to definition"; };
            "gD" = { action = "declaration"; desc = "Go to declaration"; };
            "gi" = { action = "implementation"; desc = "Go to implementation"; };
            "gt" = { action = "type_definition"; desc = "Go to type definition"; };
            "<leader>ca" = { action = "code_action"; desc = "Code action"; };
            "<leader>rn" = { action = "rename"; desc = "Rename"; };
            "<leader>cf" = { action = "format"; desc = "Format"; };
          };
          diagnostic = {
            "[d" = { action = "goto_prev"; desc = "Previous diagnostic"; };
            "]d" = { action = "goto_next"; desc = "Next diagnostic"; };
            "<leader>cd" = { action = "open_float"; desc = "Line diagnostics"; };
          };
        };
      };
    };

    # The above `gd` and `gr` telescope maps and the LSP `gd` map both want
    # the same key. Telescope's runs as a buffer-global map; the LSP one is
    # set on LspAttach as a buffer-local override, so in LSP-attached
    # buffers the LSP definition wins and elsewhere telescope tags fires.
    # Documented so future-me doesn't think it's a typo.
  };
}
