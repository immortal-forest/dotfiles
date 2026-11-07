return {

  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },
  {
    "catgoose/nvim-colorizer.lua",
    event = "User FilePost",
    opts = {
      user_default_options = {
        names = false, -- disable color names like "red"
      },
    },
    config = function(_, opts)
      require("colorizer").setup(opts)
      -- attach to current buffer on load
      vim.defer_fn(function()
        require("colorizer").attach_to_buffer(0)
      end, 0)
    end,
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
    config = function()
      require("mini.icons").setup()
    end,
  },

  {
    "folke/trouble.nvim",
    opts = {},
    cmd = "Trouble",
  },

  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
    event = { "BufReadPost", "BufWritePost", "BufNewFile" },
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "quarto" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    config = function()
      require "configs.markdown"
    end,
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
    enabled = true,
    event = "VeryLazy",
    config = function()
      require "configs.lint"
    end,
  },

  {
    "michaelrommel/nvim-silicon",
    lazy = true,
    cmd = "Silicon",
    opts = {
      -- background is set from the current theme's accent on each shot (mappings.lua)
      font = "Obel Mono Lig=34;Noto Color Emoji=34",
      num_separator = "\u{258f} ",
      theme = "Coldark-Dark",
      output = function()
        return vim.fn.expand "~/Pictures/Snapshots/" .. os.date "!%Y-%m-%dT%H-%M-%SZ" .. "_code.png"
      end,
    },
  },

  -- nvim-treesitter is on the `main` branch now (NvChad v2.5): parsers are only
  -- installed via :TSInstallAll (also run on build) and need the tree-sitter CLI.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
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
