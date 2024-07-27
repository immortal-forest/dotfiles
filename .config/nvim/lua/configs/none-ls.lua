local null_ls = require "null-ls"

return {
  sources = {
    null_ls.builtins.diagnostics.mypy,
    -- null_ls.builtins.diagnostics.cfn_lint
    -- null_ls.builtins.formatting.black,
  },
}
