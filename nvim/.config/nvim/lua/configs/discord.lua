local lastfm = require "other.lastfm"

require("cord").setup {
  editor = {
    icon = "https://raw.githubusercontent.com/vyfor/icons/refs/heads/master/icons/default/accent/nvchad.png",
    tooltip = "Hmm...",
  },
  display = {
    theme = "classic",
    flavor = "accent",
  },
  idle = {
    enabled = false,
  },
  text = {
    workspace = function(opts)
      if lastfm.song then
        return 'Listening "' .. lastfm.song .. (lastfm.artist and (" - " .. lastfm.artist) or "") .. '"'
      end
      return opts.workspace
    end,
  },
}
