require "other.lastfm"
require("cord").setup {
  timestamp = {
    reset_on_idle = false,
    reset_on_change = false,
  },
  editor = {
    client = "neovim",
    icon = "https://raw.githubusercontent.com/vyfor/icons/refs/heads/master/icons/default/accent/nvchad.png",
    tooltip = "Hmm...",
  },
  display = {
    theme = "classic",
    flavor = "accent",
  },
  idle = {
    enabled = false,
    timeout = 0,
    smart_idle = false,
  },
  text = {
    workspace = function(opts)
      if SONG then
        return ("🎶 " .. SONG .. " - " .. ARTIST)
      end
      return opts.workspace
    end,
  },
}
