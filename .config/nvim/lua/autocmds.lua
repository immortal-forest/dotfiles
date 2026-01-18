require "nvchad.autocmds"

local autocmd = vim.api.nvim_create_autocmd
local usercmd = vim.api.nvim_create_user_command

autocmd({ "BufWritePost", "BufReadPost" }, {
  callback = function()
    require("lint").try_lint()
  end,
})

autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp_attach_disable_ruff_hover", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client == nil then
      return
    end
    if client.name == "ruff" then
      -- Disable hover in favor of ty
      client.server_capabilities.hoverProvider = false
    end
  end,
  desc = "LSP: Disable hover capability from Ruff",
})

-- Enable inlay hints for LSP servers that support it
autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.server_capabilities.inlayHintProvider then
      vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
    end
  end,
  desc = "LSP: Enable inlay hints",
})

autocmd("BufDelete", {
  callback = function()
    local bufs = vim.t.bufs
    if #bufs == 1 and vim.api.nvim_buf_get_name(bufs[1]) == "" then
      vim.cmd "Nvdash"
    end
  end,
})

-- Enable/Disable formatter
usercmd("FormatDisable", function(args)
  if args.bang then
    -- :FormatDisable! disables autoformat for this buffer only
    vim.b.disable_autoformat = true
  else
    -- :FormatDisable disables autoformat globally
    vim.g.disable_autoformat = true
  end
end, {
  desc = "Disable autoformat-on-save",
  bang = true, -- allows the ! variant
})

usercmd("FormatEnable", function()
  vim.b.disable_autoformat = false
  vim.g.disable_autoformat = false
end, {
  desc = "Re-enable autoformat-on-save",
})
