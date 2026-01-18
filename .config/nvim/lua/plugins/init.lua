return {

  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },
  {
    "R-nvim/R.nvim",
    lazy = false,
    config = function()
      -- Create a table with the options to be passed to setup()
      ---@type RConfigUserOpts
      local opts = {
        hook = {
          on_filetype = function()
            vim.keymap.set("n", "<Enter>", "<Plug>RDSendLine", { buffer = 0 })
            vim.keymap.set("v", "<Enter>", "<Plug>RSendSelection", { buffer = 0 })
          end,
        },
        R_args = { "--quiet", "--no-save" },
        min_editor_width = 72,
        rconsole_width = 78,
        objbr_mappings = { -- Object browser keymap
          c = "class", -- Call R functions
          ["<localleader>gg"] = "head({object}, n = 15)", -- Use {object} notation to write arbitrary R code.
          v = function()
            -- Run lua functions
            require("r.browser").toggle_view()
          end,
        },
        disable_cmds = {
          "RClearConsole",
          "RCustomStart",
          "RSPlot",
          "RSaveClose",
        },
      }
      -- Check if the environment variable "R_AUTO_START" exists.
      -- If using fish shell, you could put in your config.fish:
      -- alias r "R_AUTO_START=true nvim"
      if vim.env.R_AUTO_START == "true" then
        opts.auto_start = "on startup"
        opts.objbr_auto_start = true
      end
      require("r").setup(opts)
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
    "echasnovski/mini.icons",
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
    ft = { "markdown", "quarto", "rmd" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
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
      background = "#89b4fa",
      font = "Maple Mono NF=34;Noto Color Emoji=34",
      num_separator = "\u{258f} ",
      theme = "Coldark-Dark",
      output = function()
        return vim.fn.expand "~/Pictures/Snapshots/" .. os.date "!%Y-%m-%dT%H-%M-%SZ" .. "_code.png"
      end,
    },
  },

  {
    "nvchad/minty",
    cmd = { "Shades", "Huefy" },
    opts = { huefy = { border = false } },
  },
}
