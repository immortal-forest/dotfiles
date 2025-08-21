local nvlsp = require "nvchad.configs.lspconfig"
local lspconfig = require "lspconfig"

nvlsp.defaults() -- loads nvchad's defaults

local servers = { "ruff", "ts_ls", "pyright", "cssls" }

-- single server setup
lspconfig.pyright.setup {
  settings = {
    pyright = {
      -- use ruff instead
      disableOrganizeImports = true,
    },
    python = {
      analysis = {
        -- Ignore all files for analysis to exclusively use Ruff for linting
        ignore = { "*" },
      },
    },
  },
}

vim.lsp.enable(servers)
