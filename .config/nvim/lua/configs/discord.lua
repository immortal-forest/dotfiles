require("cord").setup {
  usercmds = true,
  log_level = "off",
  timer = {
    interval = 1500,
    reset_on_idle = false,
    reset_on_change = false,
  },
  editor = {
    image = "nvchad",
    client = "neovim",
    tooltip = "i use arch btw",
  },
  display = {
    show_time = true,
    show_repository = false,
    show_cursor_position = false,
    swap_fields = false,
    swap_icons = false,
    workspace_blacklist = {},
  },
  lsp = {
    show_problem_count = false,
    severity = 1,
    scope = "workspace",
  },
  idle = {
    enable = false,
    show_status = true,
    timeout = 0,
    disable_on_focus = false,
    text = "Idle",
    tooltip = "💤",
  },
  text = {
    viewing = "Viewing {}",
    editing = "Editing {}",
    file_browser = "Browsing files in {}",
    plugin_manager = "Managing plugins in {}",
    lsp_manager = "Configuring LSP in {}",
    vcs = "Committing changes in {}",
    workspace = "In {}",
  },
  buttons = {
    {
      label = "View Repository",
      url = "git",
    },
  },
  assets = {
    nvdash = {
      icon = "https://raw.githubusercontent.com/vyfor/cord.nvim/refs/heads/master/assets/editor/nvchad.png",
      tooltip = "Nvdash",
    },
  },
}
