local lint = require "lint"

lint.linters_by_ft = {
  lua = { "luacheck" },
  c = { "cppcheck" },
  cpp = { "cppcheck" },
  sh = { "bash" },
}
