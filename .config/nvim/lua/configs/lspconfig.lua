local nvlsp = require "nvchad.configs.lspconfig"

nvlsp.defaults() -- loads nvchad's defaults

local servers = {
  ruff = {},
  ts_ls = {},
  pyright = {
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
  },
  r_language_server = {
    cmd = { "R", "--no-echo", "-e", "languageserver::run()" },
    filetypes = { "r", "rmd", "quarto" },
    root_dir = function(bufnr, on_dir)
      on_dir(vim.fs.root(bufnr, ".git") or vim.uv.os_homedir())
    end,
  },
}

for name, opts in pairs(servers) do
  vim.lsp.config(name, opts)
  vim.lsp.enable(name)
end
