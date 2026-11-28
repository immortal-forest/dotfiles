require "nvchad.autocmds"

local autocmd = vim.api.nvim_create_autocmd
local usercmd = vim.api.nvim_create_user_command

vim.lsp.inlay_hint.enable(true)

autocmd({ "BufWritePost", "BufReadPost" }, {
  group = vim.api.nvim_create_augroup("user_lint", { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].buftype == "" then
      require("lint").try_lint()
    end
  end,
})

autocmd("BufDelete", {
  callback = function()
    local bufs = vim.t.bufs
    if bufs and #bufs == 1 and vim.api.nvim_buf_get_name(bufs[1]) == "" then
      vim.cmd "Nvdash"
    end
  end,
})

usercmd("FormatDisable", function(args)
  if args.bang then
    vim.b.disable_autoformat = true
  else
    vim.g.disable_autoformat = true
  end
end, { desc = "Disable format on save (! for this buffer)", bang = true })

usercmd("FormatEnable", function()
  vim.b.disable_autoformat = false
  vim.g.disable_autoformat = false
end, { desc = "Re-enable format on save" })

-- recolour open nvims when matugen rewrites the theme
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

-- Obel Mono masks KEY=value only as one unwrapped, single-colour run
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
