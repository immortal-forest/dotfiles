require("cord").setup {
  timestamp = {
    reset_on_idle = false,
    reset_on_change = false,
  },
  editor = {
    client = "nvchad",
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
