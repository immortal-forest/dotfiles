-- Polls last.fm for the track you're scrobbling right now and exposes it as the
-- globals SONG / ARTIST (read by configs/discord.lua for the presence text).
--
-- Credentials live outside the repo, from either:
--   env:  LASTFM_USER, LASTFM_API_KEY
--   file: ~/.local/share/nvim/lastfm.json  ->  { "user": "...", "api_key": "..." }
-- With neither set this does nothing (no requests, no messages).

SONG, ARTIST = nil, nil

local function credentials()
  local user, key = vim.env.LASTFM_USER, vim.env.LASTFM_API_KEY
  if user and key then
    return user, key
  end
  local path = vim.fn.stdpath "data" .. "/lastfm.json"
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if ok and type(data) == "table" and data.user and data.api_key then
    return data.user, data.api_key
  end
end

local user, api_key = credentials()
if not user then
  return
end

local url = "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&format=json&limit=1"
  .. "&user="
  .. vim.uri_encode(user)
  .. "&api_key="
  .. vim.uri_encode(api_key)

local function update(out)
  -- network blips just keep the last value; the next tick retries
  if out.code ~= 0 or not out.stdout then
    return
  end
  local ok, data = pcall(vim.json.decode, out.stdout)
  local track = ok and data.recenttracks and data.recenttracks.track and data.recenttracks.track[1]
  -- "@attr.nowplaying" is only present while a track is actually playing
  if not track or not track["@attr"] then
    SONG, ARTIST = nil, nil
    return
  end
  SONG = track.name ~= "" and track.name or nil
  ARTIST = track.artist and track.artist["#text"] ~= "" and track.artist["#text"] or nil
end

local timer = vim.uv.new_timer()
timer:start(0, 12000, function()
  vim.system({ "curl", "-s", "--fail", "--max-time", "10", url }, { text = true }, vim.schedule_wrap(update))
end)
