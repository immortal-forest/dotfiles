require "nvchad.autocmds"

local autocmd = vim.api.nvim_create_autocmd
local usercmd = vim.api.nvim_create_user_command

autocmd({ "BufWritePost", "BufReadPost" }, {
  group = vim.api.nvim_create_augroup("user_lint", { clear = true }),
  callback = function(args)
    -- real files only: not help, Trouble, nvdash, terminals...
    if vim.bo[args.buf].buftype == "" then
      require("lint").try_lint()
    end
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

-- Inlay hints on by default (globally, so <leader>uh toggles every buffer)
vim.lsp.inlay_hint.enable(true)

autocmd("BufDelete", {
  callback = function()
    local bufs = vim.t.bufs
    if bufs and #bufs == 1 and vim.api.nvim_buf_get_name(bufs[1]) == "" then
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

-- Live wallpaper theme: matugen rewrites lua/themes/matugen.lua on every
-- wallpaper change (several times per setwall run, hence the debounce); when
-- that's the active theme, recompile base46 so open nvims recolour in place.
do
  local dir = vim.fn.stdpath "config" .. "/lua/themes"
  local watcher, debounce = vim.uv.new_fs_event(), vim.uv.new_timer()
  if watcher and debounce and vim.uv.fs_stat(dir) then
    watcher:start(dir, {}, function(_, fname)
      if fname ~= "matugen.lua" then
        return
      end
      debounce:stop()
      debounce:start(
        400,
        0,
        vim.schedule_wrap(function()
          if require("nvconfig").base46.theme == "matugen" then
            require("base46").load_all_highlights()
          end
        end)
      )
    end)
  end
end

-- Obel Mono masks keys (font-feature ss01) only when it sees a name and its
-- value as one stretch of same-coloured text, on one line. Highlighting colours
-- KEY and =value differently and wrapping splits long keys, which both show the
-- key. So .env files get no highlighting and no wrapping.
autocmd({ "BufWinEnter", "FileType" }, {
  group = vim.api.nvim_create_augroup("obel_mask_env", { clear = true }),
  pattern = { ".env", ".env.*", "*.env", "env", "sh", "conf", "dotenv" },
  callback = function(args)
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t")
    if not (name == ".env" or name:match "^%.env%." or name:match "%.env$") then
      return
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(args.buf) then
        return
      end
      pcall(vim.treesitter.stop, args.buf)
      vim.bo[args.buf].syntax = "off"
      for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
        vim.wo[win].wrap = false
      end
    end)
  end,
})
