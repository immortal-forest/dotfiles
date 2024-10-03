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
    theme = "minimal",
    separator_style = "round",
    order = { "mode", "file", "git", "f", "lsp_msg", "f", "linters", "diagnostics", "lsp", "cwd", "cursor" },
    modules = {
      linters = function()
        local linters = require("lint").get_running()
        if #linters == 0 then
          return "󰦕 "
        end
        return "󱉶 " .. table.concat(linters, ", ") .. " "
      end,
      f = "%=",
      lsp = function()
        local stbufnr = function()
          return vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
        end
        if rawget(vim, "lsp") and vim.version().minor >= 10 then
          for _, client in ipairs(vim.lsp.get_clients()) do
            if client.attached_buffers[stbufnr()] then
              return (vim.o.columns > 100 and "   " .. client.name .. " ") or "   LSP "
            end
          end
        end

        return ""
      end,
    },
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
