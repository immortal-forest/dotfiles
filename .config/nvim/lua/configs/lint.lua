local lint = require "lint"

lint.linters_by_ft = {
  lua = { "luacheck" },
  python = { "ruff" },
  sh = { "bash" },
  javascript = { "biomejs" },
  typescript = { "biomejs" },
}
