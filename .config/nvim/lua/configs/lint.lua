local lint = require "lint"

lint.linters_by_ft = {
  lua = { "luacheck" },
  python = { "ruff", "mypy" },
  c = { "cppcheck" },
  cpp = { "cppcheck" },
  sh = { "bash" },
}
