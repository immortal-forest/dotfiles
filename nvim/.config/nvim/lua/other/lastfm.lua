local user, api_key = "", ""
SONG = nil
ARTIST = nil
local timer = vim.uv.new_timer()
timer:start(
  0,
  12000,
  vim.schedule_wrap(function()
    vim.system(
      {
        "curl",
        "http://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user="
          .. user
          .. "&api_key="
          .. api_key
          .. "&format=json&limit=1",
        "-s",
        "--fail",
      },
      { text = true },
      vim.schedule_wrap(function(opts)
        if opts.code ~= 0 or not opts.stdout then
          print "Failed to fetch data from last.fm"
          timer:close()
          return
        end

        local data = vim.fn.json_decode(opts.stdout)
        local recenttracks = data.recenttracks
        if not recenttracks then
          print "Failed to fetch recenttracks from last.fm"
          timer:close()
          return
        end

        local track = recenttracks.track[1]
        if not track or not track["@attr"] then
          SONG = nil
          return
        end

        SONG = track.name
        ARTIST = track.artist["#text"]
        if SONG == "" then
          SONG = nil
        end
        if ARTIST == "" then
          ARTIST = nil
        end
      end)
    )
  end)
)
