local lint = require "lint"

lint.linters_by_ft = {
  python = { "ruff" },
  javascript = { "biomejs" },
  typescript = { "biomejs" },
}
