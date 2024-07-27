return {

  {
    "IogaMaster/neocord",
    event = "VeryLazy",
    init = function()
      local wk = require "which-key"
      wk.add {
        { "<leader>d", group = "discord" },
        {
          "<leader>dp",
          function()
            require "configs.discord"
          end,
          desc = "Discord Rich Presence",
        },
      }
    end,
    config = function()
      require "configs.discord"
    end,
  },

  { "echasnovski/mini.nvim", version = false },

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
    "nvimtools/none-ls.nvim",
    ft = { "python" },
    opts = function()
      return require "configs.none-ls"
    end,
  },

  {
    "mfussenegger/nvim-lint",
    enabled = true,
    event = "VeryLazy",
    config = function()
      require("lint").linters_by_ft = {
        python = { "ruff" },
      }
    end,
  },

  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "pyright",
        "mypy",
        "ruff",
        "black",
      },
    },
  },

  {
    "michaelrommel/nvim-silicon",
    lazy = true,
    cmd = "Silicon",
    init = function()
      local wk = require "which-key"
      wk.add {
        mode = { "v" },
        { "<leader>s", group = "Silicon" },
        {
          "<leader>sc",
          function()
            require("nvim-silicon").clip()
          end,
          desc = "Copy code screenshot to clipboard",
        },
        {
          "<leader>sf",
          function()
            require("nvim-silicon").file()
          end,
          desc = "Save code screenshot as file",
        },
        {
          "<leader>ss",
          function()
            require("nvim-silicon").shoot()
          end,
          desc = "Create code screenshot",
        },
      }
    end,
    config = function()
      require("silicon").setup {
        font = "JetBrainsMono Nerd Font=34;Noto Color Emoji=34",
        theme = "Coldark-Dark",
        output = function()
          return "~/Pictures/Snapshots/" .. os.date "!%Y-%m-%dT%H-%M-%SZ" .. "_code.png"
        end,
      }
    end,
  },
}
