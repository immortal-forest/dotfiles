require("cord").setup {
  timestamp = {
    reset_on_idle = false,
    reset_on_change = false,
  },
  editor = {
    client = "neovim",
    icon = "https://raw.githubusercontent.com/vyfor/icons/refs/heads/master/icons/onyx/nvchad.png",
  },
  display = {
    theme = "onyx",
  },
  idle = {
    enabled = false,
    timeout = 0,
    smart_idle = false,
  },
}
