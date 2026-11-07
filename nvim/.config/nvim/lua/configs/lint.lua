local lint = require "lint"

-- C/C++ and Lua are linted by their language servers (clangd runs clang-tidy,
-- lua_ls has its own diagnostics), so only shell needs an external linter.
lint.linters_by_ft = {
  sh = { "bash" },
}
