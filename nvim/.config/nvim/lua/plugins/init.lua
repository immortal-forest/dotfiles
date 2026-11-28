return {
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },

  {
    "catgoose/nvim-colorizer.lua",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      user_default_options = { names = false },
    },
  },

  {
    "vyfor/cord.nvim",
    branch = "master",
    event = "VeryLazy",
    build = ":Cord update",
    config = function()
      require "configs.discord"
    end,
  },

  {
    "nvim-mini/mini.icons",
    version = false,
    opts = {},
  },

  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = {},
  },

  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufWritePost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "quarto" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    opts = {
      render_modes = true,
      latex = { enabled = false },
    },
  },

  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    config = function()
      require "configs.conform"
    end,
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      require("nvchad.configs.lspconfig").defaults()
      require "configs.lspconfig"
    end,
  },

  {
    "mfussenegger/nvim-lint",
    event = "VeryLazy",
    config = function()
      -- clangd and lua_ls lint their own languages
      require("lint").linters_by_ft = { sh = { "bash" } }
    end,
  },

  {
    "michaelrommel/nvim-silicon",
    cmd = "Silicon",
    opts = {
      font = "Obel Mono Lig=34;Noto Color Emoji=34",
      num_separator = "\u{258f} ",
      theme = "Coldark-Dark",
      output = function()
        return vim.fn.expand "~/Pictures/Snapshots/" .. os.date "!%Y-%m-%dT%H-%M-%SZ" .. "_code.png"
      end,
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      -- installed with :TSInstallAll
      ensure_installed = {
        "lua",
        "luadoc",
        "printf",
        "vim",
        "vimdoc",
        "query",
        "bash",
        "c",
        "cpp",
        "python",
        "qmljs",
        "markdown",
        "markdown_inline",
        "html",
        "json",
        "yaml",
        "toml",
        "hyprlang",
        "regex",
        "diff",
        "gitcommit",
        "git_config",
      },
    },
  },

  {
    "nvchad/minty",
    cmd = { "Shades", "Huefy" },
    opts = { huefy = { border = false } },
  },
}
