local slow_format_filetypes = { "python", "sh", "css", "json", "jsonc" }

local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    sh = { "shfmt" },
    python = function(bufnr)
      if require("conform").get_formatter_info("ruff_format", bufnr).available then
        return { "ruff_format" }
      else
        return { "isort", "black" }
      end
    end,
    json = { "fixjson" },
    jsonc = { "fixjson" },
    css = { "prettier" },
    -- html = { "prettier" },
  },

  format_on_save = function(bufnr)
    if slow_format_filetypes[vim.bo[bufnr].filetype] then
      return
    end
    local function on_format(err)
      if err and err:match "timeout$" then
        slow_format_filetypes[vim.bo[bufnr].filetype] = true
      end
    end

    return { timeout_ms = 2000, lsp_format = "fallback" }, on_format
  end,
  format_after_save = function(bufnr)
    if not slow_format_filetypes[vim.bo[bufnr].filetype] then
      return
    end
    return { lsp_format = "fallback" }
  end,
}

require("conform").setup(options)
