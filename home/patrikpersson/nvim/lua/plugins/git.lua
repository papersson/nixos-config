return {
  "tpope/vim-fugitive",
  cmd = { "Git", "G", "Gstatus", "Gblame", "Gpush", "Gpull", "Gcommit", "Gdiff" },
  keys = {
    { "<leader>gg", "<cmd>Git<cr>", desc = "Git status" },
    { "<leader>gb", "<cmd>Git blame<cr>", desc = "Git blame" },
    { "<leader>gd", "<cmd>Gdiff<cr>", desc = "Git diff" },
    { "<leader>gl", "<cmd>Git log<cr>", desc = "Git log" },
    { "<leader>gp", "<cmd>Git push<cr>", desc = "Git push" },
    { "<leader>gP", "<cmd>Git pull<cr>", desc = "Git pull" },
  },
}