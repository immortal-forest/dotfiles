require "nvchad.mappings"

local map = vim.keymap.set
local wk = require "which-key"

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Todo comments
wk.add {
  mode = { "n" },
  { "<leader>td", group = "Todo comments" },
  {
    "<leader>tdt",
    "<cmd> TodoTelescope<cr>",
    desc = "Todo Telescope",
  },
}

-- Trouble
wk.add {
  mode = { "n" },
  { "<leader>t", group = "Trouble" },
  {
    "<leader>tt",
    "<cmd>Trouble diagnostics toggle<cr>",
    desc = "Toggle Diagnostics",
  },
  {
    "<leader>tb",
    "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
    desc = "Buffer Diagnostics",
  },
  {
    "<leader>ts",
    "<cmd>Trouble symbols toggle focus=false<cr>",
    desc = "Toggle Symbols",
  },
  {
    "<leader>tl",
    "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
    desc = "LSP Definitions, references & more",
  },
  {
    "<leader>tq",
    "<cmd>Trouble qflist toggle<cr>",
    desc = "Quickfix List",
  },
}

-- Markdown
wk.add {
  mode = { "n" },
  { "<leader>m", group = "Markdown" },
  {
    "<leader>mt",
    function()
      require("render-markdown").toggle()
    end,
    desc = "Toggle render markdown",
  },
}

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

-- cord
wk.add {
  mode = "n",
  { "<leader>d", group = "Discord" },
  {
    "<leader>dc",
    "<cmd> Cord presence suppress<cr>",
    desc = "Clear presence",
  },
  {
    "<leader>dr",
    "<cmd> Cord restart<cr>",
    desc = "Reconnect to Discord",
  },
  {
    "<leader>dp",
    "<cmd> Cord presence toggle<cr>",
    desc = "Toggle presence",
  },
  {
    "<leader>di",
    "<cmd> Cord idle toggle<cr>",
    desc = "Toggle idle status",
  },
}
