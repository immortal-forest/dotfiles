-- Popout follow: SUPER+O pins the newest popout window (browser
-- Picture-in-Picture, Discord call/stream popout) so it rides along to every
-- workspace you switch to — but never into a special workspace. Press again
-- to release it; it stays floating where it is on the current workspace.
--
-- Built on Hyprland's pin, which keeps the window's position and size and
-- holds it still while workspaces slide. pin only accepts floating,
-- non-fullscreen windows, so a tiled or fullscreen popout is first floated in
-- the exact box it occupies on screen.
--
-- Special workspaces: Hyprland draws pinned windows ABOVE an open special
-- workspace ("pinned always above" in its renderer), which would drag the
-- popout into the scratchpad. So while a special is open on the popout's
-- monitor it is unpinned — it drops under the special with the rest of the
-- workspace — and re-pinned when the special closes.
--
-- The following window is marked with a tag (visible in `hyprctl clients`)
-- instead of a Lua variable: a config reload builds a fresh Lua state, and
-- the tag survives it.

local M = {}

local TAG = "popout-follow"

-- Lowercased Lua patterns, tried against both the title and the initial
-- title. The initial title matters for Discord: its popout opens as
-- "Discord Popout" and then renames itself to the call/channel name.
local POPOUTS = {
	{ pattern = "^picture.in.picture$", label = "Picture-in-Picture" }, -- Firefox/Zen "Picture-in-Picture", Chromium "Picture in picture"
	{ pattern = "^discord popout$",     label = "Discord popout" },     -- Discord / Vesktop voice + stream popouts
}

local function popoutLabel(w)
	local title, initial = (w.title or ""):lower(), (w.initial_title or ""):lower()
	for _, p in ipairs(POPOUTS) do
		if title:match(p.pattern) or initial:match(p.pattern) then
			return p.label
		end
	end
end

local function isFollowing(w)
	for _, t in ipairs(w.tags or {}) do
		if t == TAG then
			return true
		end
	end
	return false
end

local function follower()
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and isFollowing(w) then
			return w
		end
	end
end

-- Newest by creation order: stable_id is a global counter Hyprland bumps for
-- every new window (as a hex string), so the largest one was opened last.
-- Popouts stashed on a special workspace (e.g. special:minimized) are skipped.
local function newestPopout()
	local best, bestId
	for _, w in ipairs(hl.get_windows()) do
		local id = tonumber(w.stable_id, 16)
		if w.mapped and id and not (w.workspace and w.workspace.special) and popoutLabel(w) and (not bestId or id > bestId) then
			best, bestId = w, id
		end
	end
	return best
end

local function specialOpenOn(mon)
	return mon ~= nil and mon.active_special_workspace ~= nil
end

local function setPinned(w, pinned)
	if w.pinned ~= pinned then
		hl.dispatch(hl.dsp.window.pin({ action = pinned and "enable" or "disable", window = w }))
	end
end

local function notify(body)
	hl.exec_cmd("notify-send -a Hyprland -u low -t 1500 Popout '" .. body .. "'")
end

function M.toggle()
	local current = follower()
	if current then
		hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG, window = current }))
		setPinned(current, false)
		notify("Stays on this workspace")
		return
	end

	local w = newestPopout()
	if not w then
		notify("No popout window open")
		return
	end

	-- Discord fullscreens its stream popout; pin refuses fullscreen windows.
	if w.fullscreen ~= 0 or w.fullscreen_client ~= 0 then
		hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set", window = w }))
	end
	-- Float in place: floating alone would snap it to its last floating size.
	if not w.floating then
		local at, size = w.at, w.size
		hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
		hl.dispatch(hl.dsp.window.resize({ x = size.x, y = size.y, window = w }))
		hl.dispatch(hl.dsp.window.move({ x = at.x, y = at.y, window = w }))
	end

	hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = w }))
	-- Pinning assigns it to its monitor's active (never special) workspace, so
	-- a popout left on another workspace comes to you. If a special is open
	-- right now, workspace.special_active pins it once that closes.
	setPinned(w, not specialOpenOn(w.monitor))
	notify(popoutLabel(w) .. " follows you")
end

-- ws is the special workspace that opened, or nil when it closed.
function M.onSpecial(ws, mon)
	local w = follower()
	if not (w and mon and w.monitor) or w.monitor.id ~= mon.id then
		return
	end
	setPinned(w, ws == nil)
end

hl.bind("SUPER + O", M.toggle, { description = "Popout: follow across workspaces (newest PiP / Discord popout)" })

hl.on("workspace.special_active", M.onSpecial)

-- A special toggled while the config was mid-reload had no listener; re-sync.
hl.on("config.reloaded", function()
	local w = follower()
	if w then
		setPinned(w, not specialOpenOn(w.monitor))
	end
end)

return M
