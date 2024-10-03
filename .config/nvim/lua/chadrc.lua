-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v2.5/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "catppuccin",

  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },
  theme_toggle = { "catppuccin", "chadracula-evondev" },
}

M.ui = {
  telescope = {
    style = "bordered",
  },
  statusline = {
    theme = "default",
    separator_style = "round",
  },
}

M.nvdash = {
  load_on_startup = true,
}

M.mason = {
  pkgs = {
    "pyright",
    -- "mypy",
    "ruff",
    "black",
    "lua-language-server",
    "typescript-language-server",
    "biome",
    "stylua",
    "shfmt",
    "fixjson",
    "prettier",
  },
}

return M
