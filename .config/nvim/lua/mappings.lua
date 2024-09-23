require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
map("n", "<C-h>", "<cmd> TmuxNavigateLeft<CR>", { desc = "Tmux window left" })
map("n", "<C-l>", "<cmd> TmuxNavigateRight<CR>", { desc = "Tmux window right" })
map("n", "<C-j>", "<cmd> TmuxNavigateDown<CR>", { desc = "Tmux window down" })
map("n", "<C-k>", "<cmd> TmuxNavigateUp<CR>", { desc = "Tmux window up" })
