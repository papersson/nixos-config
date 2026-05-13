-- Core Navigation Keymaps

-- Quick escape
vim.keymap.set("i", "jj", "<Esc>", { noremap = true, silent = true })

-- Better window navigation
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Buffer navigation
vim.keymap.set("n", "[b", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
vim.keymap.set("n", "]b", "<cmd>bnext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "<leader>bd", "<cmd>bd<cr>", { desc = "Delete buffer" })
vim.keymap.set("n", "<leader>bD", "<cmd>bd!<cr>", { desc = "Force delete buffer" })

-- Quickfix navigation
vim.keymap.set("n", "[q", "<cmd>cprev<cr>", { desc = "Previous quickfix" })
vim.keymap.set("n", "]q", "<cmd>cnext<cr>", { desc = "Next quickfix" })
vim.keymap.set("n", "<leader>co", "<cmd>copen<cr>", { desc = "Open quickfix" })
vim.keymap.set("n", "<leader>cc", "<cmd>cclose<cr>", { desc = "Close quickfix" })

-- Location list navigation
vim.keymap.set("n", "[l", "<cmd>lprev<cr>", { desc = "Previous location" })
vim.keymap.set("n", "]l", "<cmd>lnext<cr>", { desc = "Next location" })
vim.keymap.set("n", "<leader>lo", "<cmd>lopen<cr>", { desc = "Open location list" })
vim.keymap.set("n", "<leader>lc", "<cmd>lclose<cr>", { desc = "Close location list" })

-- Search and replace
vim.keymap.set("n", "<leader>rw", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], { desc = "Replace word under cursor" })
vim.keymap.set("v", "<leader>r", [[:s/]], { desc = "Replace in selection" })

-- Keep cursor centered when scrolling
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Scroll down" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Scroll up" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result" })

-- Better indenting
vim.keymap.set("v", "<", "<gv", { desc = "Indent left" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right" })

-- Move lines
vim.keymap.set("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
vim.keymap.set("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
vim.keymap.set("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Jump list navigation (making them more prominent)
vim.keymap.set("n", "<leader>jo", "<C-o>", { desc = "Jump back" })
vim.keymap.set("n", "<leader>ji", "<C-i>", { desc = "Jump forward" })

-- Mark navigation
vim.keymap.set("n", "<leader>ml", "<cmd>marks<cr>", { desc = "List marks" })
vim.keymap.set("n", "<leader>md", "<cmd>delmarks a-z<cr>", { desc = "Delete all marks" })

-- Tags navigation (requires ctags)
vim.keymap.set("n", "<leader>tj", "<C-]>", { desc = "Jump to tag" })
vim.keymap.set("n", "<leader>tb", "<C-t>", { desc = "Jump back from tag" })
vim.keymap.set("n", "<leader>ts", "g]", { desc = "List matching tags" })

-- Macro helpers
vim.keymap.set("n", "Q", "@q", { desc = "Play macro q" })
vim.keymap.set("v", "Q", ":norm @q<cr>", { desc = "Play macro q on selection" })

-- Clear search highlighting
vim.keymap.set("n", "<leader>h", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- Yank to system clipboard
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Yank line to clipboard" })

-- Paste from system clipboard
vim.keymap.set({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>P", [["+P]], { desc = "Paste before from clipboard" })

-- Quick save
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })
vim.keymap.set("n", "<leader>W", "<cmd>wa<cr>", { desc = "Save all files" })

-- Quick quit
vim.keymap.set("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
vim.keymap.set("n", "<leader>Q", "<cmd>qa<cr>", { desc = "Quit all" })

-- Split management
vim.keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split vertical" })
vim.keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split horizontal" })
vim.keymap.set("n", "<leader>se", "<C-w>=", { desc = "Equal splits" })
vim.keymap.set("n", "<leader>sx", "<cmd>close<cr>", { desc = "Close split" })
