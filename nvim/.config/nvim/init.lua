vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- matugen rewrote the wallpaper theme while nvim was closed: recompile the cache
local matugen_theme = vim.uv.fs_stat(vim.fn.stdpath "config" .. "/lua/themes/matugen.lua")
local theme_cache = vim.uv.fs_stat(vim.g.base46_cache .. "defaults")
if
  matugen_theme
  and require("nvconfig").base46.theme == "matugen"
  and (not theme_cache or matugen_theme.mtime.sec >= theme_cache.mtime.sec)
then
  require("base46").compile()
end

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "autocmds"

vim.schedule(function()
  require "mappings"
end)
