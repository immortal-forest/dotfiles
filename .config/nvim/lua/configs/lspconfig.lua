local on_attach = require("nvchad.configs.lspconfig").on_attach
local capabilities = require("nvchad.configs.lspconfig").capabilities

local lspconfig = require "lspconfig"

lspconfig.pyright.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  filetypes = { "python" },
  -- settings = {
  -- pyright = {
  -- use ruff instead
  -- disableOrganizeImports = true,
  -- },
  -- python = {
  -- analysis = {
  -- Ignore all files for analysis to exclusively use Ruff for linting
  -- ignore = { "*" },
  -- },
  -- },
  -- },
}
