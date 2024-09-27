require "nvchad.mappings"

local map = vim.keymap.set
local wk = require "which-key"

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Silicon
wk.add {
  mode = { "v" },
  { "<leader>s", group = "Silicon" },
  {
    "<leader>sc",
    function()
      require("nvim-silicon").clip()
    end,
    desc = "Copy code screenshot to clipboard",
  },
  {
    "<leader>sf",
    function()
      require("nvim-silicon").file()
    end,
    desc = "Save code screenshot as file",
  },
  {
    "<leader>ss",
    function()
      require("nvim-silicon").shoot()
    end,
    desc = "Create code screenshot",
  },
}

-- Tmux Navigation
wk.add {
  mode = "n",
  { "", group = "TmuxNav" },
  {
    "<C-h>",
    "<cmd> TmuxNavigateLeft<cr>",
    desc = "Tmux window left",
  },
  {
    "<C-l>",
    "<cmd> TmuxNavigateRight<cr>",
    desc = "Tmux window right",
  },
  {
    "<C-j>",
    "<cmd> TmuxNavigateDown<cr>",
    desc = "Tmux window down",
  },
  {
    "<C-k>",
    "<cmd> TmuxNavigateUp<cr>",
    desc = "Tmux window up",
  },
}
