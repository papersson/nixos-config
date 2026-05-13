return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
  cmd = "Telescope",
  keys = {
    -- File navigation
    { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
    { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
    { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
    { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
    { "<leader>fo", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
    
    -- Search variations
    { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Grep word under cursor" },
    { "gr", "<cmd>Telescope grep_string<cr>", desc = "Grep references" },
    
    -- Navigation
    { "<leader>fm", "<cmd>Telescope marks<cr>", desc = "Marks" },
    { "<leader>fj", "<cmd>Telescope jumplist<cr>", desc = "Jump list" },
    { "<leader>fr", "<cmd>Telescope registers<cr>", desc = "Registers" },
    
    -- Git
    { "<leader>gc", "<cmd>Telescope git_commits<cr>", desc = "Git commits" },
    { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git status" },
    
    -- Tags (requires ctags)
    { "gd", "<cmd>Telescope tags<cr>", desc = "Go to definition (tags)" },
    { "<leader>ft", "<cmd>Telescope tags<cr>", desc = "Tags" },
    { "<leader>fT", "<cmd>Telescope current_buffer_tags<cr>", desc = "Buffer tags" },
    
    -- Vim internals
    { "<leader>fc", "<cmd>Telescope commands<cr>", desc = "Commands" },
    { "<leader>fk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
    { "<leader>f:", "<cmd>Telescope command_history<cr>", desc = "Command history" },
    { "<leader>f/", "<cmd>Telescope search_history<cr>", desc = "Search history" },
    
    -- Quickfix
    { "<leader>fq", "<cmd>Telescope quickfix<cr>", desc = "Quickfix list" },
    { "<leader>fl", "<cmd>Telescope loclist<cr>", desc = "Location list" },
  },
  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")
    
    telescope.setup({
      defaults = {
        mappings = {
          i = {
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
            ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
            ["<M-q>"] = actions.send_to_qflist + actions.open_qflist,
            ["<C-x>"] = actions.select_horizontal,
            ["<C-v>"] = actions.select_vertical,
            ["<C-t>"] = actions.select_tab,
            ["<C-u>"] = actions.preview_scrolling_up,
            ["<C-d>"] = actions.preview_scrolling_down,
          },
          n = {
            ["q"] = actions.close,
            ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
          },
        },
        layout_config = {
          horizontal = {
            preview_width = 0.55,
            results_width = 0.8,
          },
          vertical = {
            mirror = false,
          },
          width = 0.87,
          height = 0.80,
        },
        path_display = { "truncate" },
        winblend = 0,
        border = {},
        borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
        color_devicons = true,
      },
      pickers = {
        find_files = {
          find_command = { "rg", "--files", "--hidden", "--glob", "!.git/*" },
        },
        live_grep = {
          additional_args = function()
            return { "--hidden", "--glob", "!.git/*" }
          end,
        },
        grep_string = {
          additional_args = function()
            return { "--hidden", "--glob", "!.git/*" }
          end,
        },
      },
      extensions = {
        fzf = {
          fuzzy = true,
          override_generic_sorter = true,
          override_file_sorter = true,
          case_mode = "smart_case",
        },
      },
    })
    
    -- Load extensions
    telescope.load_extension("fzf")
  end,
}