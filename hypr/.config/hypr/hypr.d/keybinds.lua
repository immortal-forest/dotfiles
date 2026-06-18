local apps = require("apps")
local mainMod = "SUPER"
local screenshot = "~/.config/scripts/screenshot.sh"

-- Window / session
hl.bind(mainMod .. " + Q",      hl.dsp.window.close())
hl.bind("ALT + F4",             hl.dsp.window.close())
hl.bind(mainMod .. " + Delete", hl.dsp.exit())
hl.bind(mainMod .. " + W",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + G",      hl.dsp.group.toggle())
hl.bind("ALT + Return",         hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + L",      hl.dsp.exec_cmd("hyprlock"), { locked = true })
-- TODO: shell — idle inhibitor toggle
-- hl.bind(mainMod .. " + I", ...)
-- TODO: shell — bar toggle
-- hl.bind("CTRL + ALT + W", ...)

-- Apps
hl.bind(mainMod .. " + T",         hl.dsp.exec_cmd(apps.terminal .. " +new-window"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("kitty -e"))
hl.bind(mainMod .. " + F",         hl.dsp.exec_cmd(apps.browser))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("firefox"))
-- TODO: shell — launcher
-- hl.bind(mainMod .. " + R", ...)
-- TODO: shell — clipboard picker
-- hl.bind(mainMod .. " + V", ...)
-- TODO: shell — control center
-- hl.bind(mainMod .. " + B", ...)
-- TODO: shell — settings panel
-- hl.bind(mainMod .. " + comma", ...)
-- TODO: shell — wallpaper picker
-- hl.bind(mainMod .. " + SHIFT + comma", ...)

-- Brightness
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })

-- Volume
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),      { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),    { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),       { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })

-- Media
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"),       { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Screenshots
hl.bind(mainMod .. " + P",        hl.dsp.exec_cmd(screenshot .. " s"))
hl.bind(mainMod .. " + CTRL + P", hl.dsp.exec_cmd(screenshot .. " sf"))
hl.bind(mainMod .. " + ALT + P",  hl.dsp.exec_cmd(screenshot .. " m"))
hl.bind("Print",                   hl.dsp.exec_cmd(screenshot .. " p"), { locked = true })

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind("ALT + Tab",            hl.dsp.focus({ direction = "down" }))

-- Workspaces 1–10 on current monitor (r~N = relative monitor workspace)
for i = 1, 10 do
	local key = tostring(i % 10)
	hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = "r~" .. i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = "r~" .. i }))
	hl.bind(mainMod .. " + ALT + " .. key,   hl.dsp.exec_raw("movetoworkspacesilent " .. i))
end

-- Relative workspace navigation
hl.bind(mainMod .. " + CTRL + right", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.focus({ workspace = "empty" }))

-- Resize windows (repeating)
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.exec_raw("resizeactive 30 0"),  { repeating = true })
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.exec_raw("resizeactive -30 0"), { repeating = true })
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.exec_raw("resizeactive 0 -30"), { repeating = true })
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.exec_raw("resizeactive 0 30"),  { repeating = true })

-- Move window to relative workspace
hl.bind(mainMod .. " + CTRL + ALT + right", hl.dsp.window.move({ workspace = "r+1" }))
hl.bind(mainMod .. " + CTRL + ALT + left",  hl.dsp.window.move({ workspace = "r-1" }))

-- Monitor workspace management
hl.bind(mainMod .. " + CTRL + S", hl.dsp.workspace.swap_monitors({ monitor1 = 0, monitor2 = 1 }))
hl.bind(mainMod .. " + CTRL + 0", hl.dsp.exec_raw("movecurrentworkspacetomonitor 0"))
hl.bind(mainMod .. " + CTRL + 1", hl.dsp.exec_raw("movecurrentworkspacetomonitor 1"))

-- Float-aware move: pixels for floating, tile direction for tiled (pure Lua, no shell)
local function floatMove(dx, dy, dir)
	return function()
		local win = hl.get_active_window()
		if win and win.floating then
			hl.dispatch(hl.dsp.exec_raw(string.format("moveactive %d %d", dx, dy)))
		else
			hl.dispatch(hl.dsp.exec_raw("movewindow " .. dir))
		end
	end
end
hl.bind(mainMod .. " + SHIFT + CTRL + left",  floatMove(-30, 0,   "l"), { repeating = true })
hl.bind(mainMod .. " + SHIFT + CTRL + right", floatMove(30,  0,   "r"), { repeating = true })
hl.bind(mainMod .. " + SHIFT + CTRL + up",    floatMove(0,   -30, "u"), { repeating = true })
hl.bind(mainMod .. " + SHIFT + CTRL + down",  floatMove(0,   30,  "d"), { repeating = true })

-- Mouse scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mouse drag / resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + Z",         hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + X",         hl.dsp.window.resize(), { mouse = true })

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S",       hl.dsp.workspace.toggle_special())
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_raw("movetoworkspacesilent special"))
