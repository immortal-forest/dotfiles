return {

  -- {
  --   "andweeb/presence.nvim",
  --   lazy = false,
  --   init = function()
  --     local wk = require "which-key"
  --     wk.register {
  --       ["d"] = {
  --         name = "Discord",
  --         ["p"] = {
  --           function()
  --             require "custom.discord"
  --           end,
  --           "Discord Rich Presence",
  --         },
  --       },
  --     }
  --   end,
  --   config = function()
  --     require "custom.discord"
  --   end,
  -- },

  {
    "IogaMaster/neocord",
    event = "VeryLazy",
    init = function()
      local wk = require "which-key"
      wk.register {
        ["d"] = {
          name = "Discord",
          ["p"] = {
            function()
              require "custom.discord"
            end,
            "Discord Rich Presence",
          },
        },
      }
    end,
    config = function()
      require "custom.discord"
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
      wk.register({
        ["s"] = {
          name = "Silicon",
          ["s"] = {
            function()
              require("nvim-silicon").shoot()
            end,
            "Create code screenshot",
          },
          ["f"] = {
            function()
              require("nvim-silicon").file()
            end,
            "Save code screenshot as file",
          },
          ["c"] = {
            function()
              require("nvim-silicon").clip()
            end,
            "Copy code screenshot to clipboard",
          },
        },
      }, { prefix = "<leader>", mode = "v" })
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
