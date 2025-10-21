local slow_format_filetypes =
  { "lua", "python", "sh", "css", "json", "jsonc", "c", "javascript", "typescript", "markdown" }

local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    sh = { "shfmt" },
    python = { "ruff_organize_imports", "ruff_fix", "ruff_format" },
    r = { "air" },
    c = { "astyle", "uncrustify" },
    json = { "fixjson" },
    jsonc = { "fixjson" },
    javascript = { "biome", "biome-check" },
    typescript = { "biome", "biome-check" },
    javascriptreact = { "biome", "biome-check" },
    typescriptreact = { "biome", "biome-check" },
    css = { "prettier" },
    scss = { "prettier" },
    -- html = { "prettier" },
    markdown = { "mdformat" },
  },

  format_on_save = function(bufnr)
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
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
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
    if not slow_format_filetypes[vim.bo[bufnr].filetype] then
      return
    end
    return { lsp_format = "fallback" }
  end,
}

require("conform").setup(options)
