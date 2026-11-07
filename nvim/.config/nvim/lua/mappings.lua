require "nvchad.mappings"

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Toggles
map("n", "<leader>uh", function()
  local on = not vim.lsp.inlay_hint.is_enabled()
  vim.lsp.inlay_hint.enable(on)
  vim.notify("Inlay hints " .. (on and "on" or "off"))
end, { desc = "Toggle inlay hints" })
map("n", "<leader>uf", function()
  vim.g.disable_autoformat = not vim.g.disable_autoformat
  vim.notify("Format on save " .. (vim.g.disable_autoformat and "off" or "on"))
end, { desc = "Toggle format on save" })

local ok, wk = pcall(require, "which-key")
if not ok then
  return
end

wk.add { { "<leader>u", group = "Toggle" } }

-- NvChad's diagnostic loclist sat inside the Discord <leader>d group; Trouble covers it
pcall(vim.keymap.del, "n", "<leader>ds")

-- Diagnostics: ]e / [e jump errors only (]d / [d are Neovim defaults)
map("n", "]e", function()
  vim.diagnostic.jump { count = 1, severity = vim.diagnostic.severity.ERROR }
end, { desc = "Next error" })
map("n", "[e", function()
  vim.diagnostic.jump { count = -1, severity = vim.diagnostic.severity.ERROR }
end, { desc = "Prev error" })

-- ]q / [q walk the Trouble list when it's open, else the quickfix list
map("n", "]q", function()
  if require("trouble").is_open() then
    require("trouble").next { skip_groups = true, jump = true }
  else
    pcall(vim.cmd.cnext)
  end
end, { desc = "Next Trouble/quickfix item" })
map("n", "[q", function()
  if require("trouble").is_open() then
    require("trouble").prev { skip_groups = true, jump = true }
  else
    pcall(vim.cmd.cprev)
  end
end, { desc = "Prev Trouble/quickfix item" })

-- ]t / [t jump between TODO/FIXME/... comments
map("n", "]t", function()
  require("todo-comments").jump_next()
end, { desc = "Next todo comment" })
map("n", "[t", function()
  require("todo-comments").jump_prev()
end, { desc = "Prev todo comment" })

-- Trouble (<leader>th stays NvChad's theme picker)
wk.add {
  mode = { "n" },
  { "<leader>t", group = "Trouble" },
  { "<leader>tt", "<cmd>Trouble diagnostics toggle<cr>", desc = "Workspace diagnostics" },
  { "<leader>tb", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
  { "<leader>ts", "<cmd>Trouble symbols toggle focus=false win.position=right<cr>", desc = "Symbols" },
  { "<leader>tl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP defs, refs & calls" },
  { "<leader>tq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list" },
  { "<leader>tL", "<cmd>Trouble loclist toggle<cr>", desc = "Location list" },
  { "<leader>tc", "<cmd>Trouble todo toggle<cr>", desc = "Todo comments" },
  { "<leader>tC", "<cmd>TodoTelescope<cr>", desc = "Todo comments (Telescope)" },
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

-- Silicon: screenshot backdrop follows the theme accent (wallpaper colour with matugen)
local function silicon(action)
  return function()
    local s = require "nvim-silicon"
    local ok, c = pcall(require("base46").get_theme_tb, "base_30")
    s.options.background = ok and c.nord_blue or "#89b4fa"
    s[action]()
  end
end

wk.add {
  mode = { "v" },
  { "<leader>s", group = "Silicon" },
  { "<leader>sc", silicon "clip", desc = "Copy code screenshot to clipboard" },
  { "<leader>sf", silicon "file", desc = "Save code screenshot as file" },
  { "<leader>ss", silicon "shoot", desc = "Create code screenshot" },
}

-- Tmux Navigation
wk.add {
  mode = "n",
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
