-- Options: https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.base46 = {
  -- written by matugen on every wallpaper change
  theme = "matugen",
  theme_toggle = { "matugen", "yoru" },
  integrations = { "trouble", "todo", "render-markdown" },
  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },
}

if not vim.uv.fs_stat(vim.fn.stdpath "config" .. "/lua/themes/matugen.lua") then
  M.base46.theme = "yoru"
end

M.mason = {
  pkgs = { "ty", "shellcheck" },
}

-- nvim-colorizer already highlights colours
M.colorify = { enabled = false }

M.ui = {
  cmp = {
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
      f = "%=",
      linters = function()
        local linters = require("lint").get_running()
        if #linters == 0 then
          return "󰦕  "
        end
        return "󱉶 " .. table.concat(linters, ", ") .. " "
      end,
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
