return {
  -- Tell LazyVim to load gruvbox as the default colorscheme
  { "LazyVim/LazyVim", opts = { colorscheme = "gruvbox" } },

  {
  "ellisonleao/gruvbox.nvim",
  priority = 1000,
  config = function()
    require("gruvbox").setup({
      -- Gruvbox settings
      transparent_mode = true,
      contrast = "soft",
      dim_inactive = true,
      italic = {
        strings = false,
        emphasis = false,
        comments = false,
        operators = false,
        folds = false,
      },
      -- Add these overrides for better Neo-Tree and Treesitter integration
      overrides = {
        -- Neo-Tree-specific highlights
        NeoTreeNormal = { bg = "NONE", fg = "#ebdbb2" },
        NeoTreeNormalNC = { bg = "NONE", fg = "#ebdbb2" },
        NeoTreeCursorLine = { bg = "#3c3836" },

        -- Treesitter overrides
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
      },
    })

    -- LazyVim handles `:colorscheme gruvbox` via opts.colorscheme above
  end,
  },
}
