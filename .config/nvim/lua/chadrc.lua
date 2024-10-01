-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v2.5/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.ui = {
  theme = "catppuccin",
  statusline = {
    theme = "minimal",
    separator_style = "round",
  },

  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },

  nvdash = {
    load_on_startup = true,
  },
}

M.mason = {
  pkgs = {
    "pyright",
    "mypy",
    "ruff",
    "black",
    "lua-language-server",
    "stylua",
    "shfmt",
    "fixjson",
    "prettier",
  },
}

return M
