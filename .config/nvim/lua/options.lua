require "nvchad.options"

local o = vim.o
o.cursorlineopt = "both" -- to enable cursorline!

local opt = vim.opt

opt.relativenumber = true

vim.filetype.add {
  pattern = {
    [".*/hypr/.*%.conf"] = "hyprlang",
  },
}
