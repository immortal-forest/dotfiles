local servers = {
  clangd = {
    cmd = {
      "clangd",
      "--background-index",
      "--clang-tidy",
      "--query-driver=/usr/bin/gcc,/usr/bin/g++",
      "--header-insertion=never",
      "--completion-style=detailed",
      "--function-arg-placeholders=true",
      "--fallback-style=llvm",
    },
    init_options = {
      usePlaceholders = true,
      completeUnimported = true,
      clangdFileStatus = true,
    },
  },
  r_language_server = {},
  ruff = {},
  ty = {},
}

for name, opts in pairs(servers) do
  vim.lsp.config(name, opts)
  vim.lsp.enable(name)
end
