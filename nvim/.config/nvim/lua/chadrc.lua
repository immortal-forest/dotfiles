-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  -- "matugen" = lua/themes/matugen.lua, written by matugen on every wallpaper
  -- change (see matugen/.config/matugen/templates/nvim*.lua) and hot-reloaded
  -- by the watcher in autocmds.lua.
  theme = "matugen",
  integrations = { "trouble", "todo", "render-markdown" },

  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },
  theme_toggle = { "matugen", "yoru" },
}

-- Fresh machine where matugen hasn't run yet: fall back to a stock theme.
if M.base46.theme == "matugen" and not vim.uv.fs_stat(vim.fn.stdpath "config" .. "/lua/themes/matugen.lua") then
  M.base46.theme = "yoru"
end

M.lsp = {
  signature = true,
}

-- :MasonInstallAll installs every server/formatter/linter the config uses.
-- ty has no NvChad name mapping, so it's listed here; clangd, clang-format and
-- qmlls come from the system packages.
M.mason = {
  pkgs = { "ty", "shellcheck" },
  skip = { "clangd", "clang-format" },
}

M.ui = {
  cmp = {
    icons = true,
    lspkind_text = true,
    style = "atom_colored",
  },
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
          return "󰦕 " .. " "
        end
        return "󱉶 " .. table.concat(linters, ", ") .. " "
      end,
      f = "%=",
      lsp = function()
        local buf = vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
        local client = vim.lsp.get_clients({ bufnr = buf })[1]
        if not client then
          return ""
        end
        return (vim.o.columns > 100 and "  " .. client.name .. " ") or "  LSP "
      end,
    },
  },
}

M.nvdash = {
  load_on_startup = true,
}

return M
