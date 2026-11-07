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
  ruff = {},
  ty = {},
  -- Arch ships qmlls as qmlls6. Import paths (Quickshell etc.) come from the
  -- .qmlls.ini Quickshell writes into the shell root on every reload.
  qmlls = { cmd = { "qmlls6" } },
  bashls = {},
  jsonls = {},
}

for name, opts in pairs(servers) do
  vim.lsp.config(name, opts)
  vim.lsp.enable(name)
end

-- Go-to keys. Defined after NvChad's LspAttach, so these buffer maps win.
-- Trouble's lsp_* modes jump straight there when there's one result and open
-- a list when there are several.
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("user_lsp_goto", { clear = true }),
  callback = function(args)
    local buf = args.buf
    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = "LSP " .. desc })
    end
    local function trouble(mode)
      return "<cmd>Trouble " .. mode .. " focus=true<cr>"
    end

    map("gd", trouble "lsp_definitions", "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("grr", trouble "lsp_references", "References")
    map("gri", trouble "lsp_implementations", "Implementations")
    map("grt", trouble "lsp_type_definitions", "Type definition")
    map("grI", trouble "lsp_incoming_calls", "Incoming calls")
    map("grO", trouble "lsp_outgoing_calls", "Outgoing calls")
    map("gO", trouble "symbols toggle focus=false win.position=right", "Document symbols")
    map("grn", require "nvchad.lsp.renamer", "Rename")
    map("gl", vim.diagnostic.open_float, "Line diagnostics")

    -- now covered by grt / Trouble
    pcall(vim.keymap.del, "n", "<leader>D", { buffer = buf })
  end,
})

-- ]d / [d show the diagnostic float after jumping; ]e / [e jump errors only
vim.diagnostic.config {
  jump = {
    on_jump = function(_, bufnr)
      vim.diagnostic.open_float { bufnr = bufnr, scope = "cursor", focus = false }
    end,
  },
}
