local apps = require("apps")
local mainMod = "SUPER"
local screenshot = "hyprshot -m"

-- Window / session
hl.bind(mainMod .. " + Q",      hl.dsp.window.close())
hl.bind("ALT + F4",             hl.dsp.window.close())
hl.bind(mainMod .. " + Delete", hl.dsp.exit())
hl.bind(mainMod .. " + W",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + G",      hl.dsp.group.toggle())
hl.bind("ALT + Return",         hl.dsp.window.fullscreen())
-- TODO: shell — idle inhibitor toggle
-- hl.bind(mainMod .. " + I", ...)
-- TODO: shell — bar toggle
-- hl.bind("CTRL + ALT + W", ...)

-- Apps
hl.bind(mainMod .. " + T",         hl.dsp.exec_cmd(apps.terminal .. " +new-window"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("kitty -e"))
hl.bind(mainMod .. " + F",         hl.dsp.exec_cmd(apps.browser))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("firefox"))
-- Shell (astralis — Quickshell IPC; see quickshell/astralis/shell.qml)
--   bridge: qs -c astralis ipc call pill <surface> "<monitor>"
--   astralis: qs IPC is arity-strict — the trailing "" (empty monitor arg,
--   resolved shell-side to the focused monitor) is REQUIRED or the call
--   errors out silently.
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd('qs -c astralis ipc call pill launcher ""'))      -- app launcher
hl.bind(mainMod .. " + M",     hl.dsp.exec_cmd('qs -c astralis ipc call pill media ""'))         -- media / now-playing
hl.bind(mainMod .. " + C",     hl.dsp.exec_cmd('qs -c astralis ipc call pill wallpaper ""'))     -- wallpaper picker
hl.bind(mainMod .. " + V",     hl.dsp.exec_cmd('qs -c astralis ipc call pill clipboard ""'))     -- clipboard history
hl.bind(mainMod .. " + L",      hl.dsp.exec_cmd("loginctl lock-session"))                        -- lock screen (astralis WlSessionLock)
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd('qs -c astralis ipc call power toggle'))          -- full-screen power / session menu
hl.bind(mainMod .. " + N",     hl.dsp.exec_cmd('qs -c astralis ipc call pill notifications ""')) -- astralis: notification center
hl.bind(mainMod .. " + A",     hl.dsp.exec_cmd('qs -c astralis ipc call pill mixer ""'))         -- astralis: audio mixer
hl.bind(mainMod .. " + D",     hl.dsp.exec_cmd('qs -c astralis ipc call pill calendar ""'))      -- astralis: calendar
hl.bind(mainMod .. " + K",     hl.dsp.exec_cmd('qs -c astralis ipc call pill link ""'))          -- astralis: link (wifi / bluetooth)
hl.bind(mainMod .. " + B",     hl.dsp.exec_cmd("qs -c astralis ipc call visualizer toggle"))     -- fullscreen visualizer
-- SHIFT because plain SUPER+S is the scratch special-workspace toggle below.
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd('qs -c astralis ipc call pill sysmon ""'))    -- astralis: system monitor
hl.bind(mainMod .. " + comma",     hl.dsp.exec_cmd('qs -c astralis ipc call pill settings ""'))  -- astralis: settings
-- Screen recording (astralis 録 → gpu-screen-recorder / wl-screenrec / wf-recorder).
-- The surface picks the source and holds the settings; the two direct binds skip
-- it entirely and are start/stop toggles, so the same key ends the take.
hl.bind(mainMod .. " + R",         hl.dsp.exec_cmd('qs -c astralis ipc call pill recorder ""'))  -- astralis: recorder surface
hl.bind(mainMod .. " + ALT + R",   hl.dsp.exec_cmd("qs -c astralis ipc call recorder toggle"))   -- astralis: record this screen / stop
hl.bind(mainMod .. " + CTRL + R",  hl.dsp.exec_cmd("qs -c astralis ipc call recorder region"))   -- astralis: record a region / stop
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("sh -c 'qs -c astralis kill; sleep 0.3; qs -c astralis -d'"))  -- astralis: relaunch the shell
-- astralis: stash/restore the focused window on special:minimized — the pill's
-- hover tray shows the stashed windows as app-icon chips that restore on click.
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("~/.config/quickshell/astralis/scripts/special-toggle.sh minimized"))

-- Brightness — route through the shell (updates its state + flashes the OSD),
-- falling back to raw brightnessctl if astralis isn't running.
-- `locked` (bindl): keeps working from the lockscreen. `repeating` (binde):
-- keeps stepping while the key is held. `dont_inhibit` (bindp): bypasses a
-- fullscreen app/game's keybind-inhibit request, so brightness always
-- responds like a real hardware key regardless of what's focused.
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("sh -c 'qs -c astralis ipc call brightness change -- -0.05 || brightnessctl -e4 -n2 set 5%-'"), { locked = true, repeating = true, dont_inhibit = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("sh -c 'qs -c astralis ipc call brightness change 0.05 || brightnessctl -e4 -n2 set 5%+'"),    { locked = true, repeating = true, dont_inhibit = true })

-- Volume — same reasoning: locked + dont_inhibit so mute/level always
-- respond; repeating only on the steppable up/down binds.
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),      { locked = true, dont_inhibit = true })
-- Mic mute — route through the shell (mutes the Pipewire default source and
-- flashes the mic OSD), falling back to raw wpctl if astralis isn't running.
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("sh -c 'qs -c astralis ipc call mic toggle || wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle'"), { locked = true, dont_inhibit = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),       { locked = true, repeating = true, dont_inhibit = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, dont_inhibit = true })

-- Media — astralis: Play/Next/Prev route through the shell's GlobalShortcut
-- handlers (shell.qml appid "quickshell" → Players singleton), replacing the
-- playerctl exec binds (both on the same key would double-fire). Stop keeps
-- playerctl (no shell handler for it). No `repeating` here — repeat-skipping
-- tracks while a media key is held isn't wanted — but `dont_inhibit` still
-- applies so a fullscreen game/video doesn't swallow play/pause/skip.
hl.bind("XF86AudioPlay", hl.dsp.global("quickshell:mediaToggle"), { locked = true, dont_inhibit = true }) -- astralis
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"),       { locked = true, dont_inhibit = true })
hl.bind("XF86AudioNext", hl.dsp.global("quickshell:mediaNext"),   { locked = true, dont_inhibit = true }) -- astralis
hl.bind("XF86AudioPrev", hl.dsp.global("quickshell:mediaPrev"),   { locked = true, dont_inhibit = true }) -- astralis
-- pre-astralis playerctl forms, restore if the shell is retired:
-- hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, dont_inhibit = true })
-- hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true, dont_inhibit = true })
-- hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true, dont_inhibit = true })

-- Screenshots — deliberately NOT `locked`: hyprshot's region/freeze pickers
-- are interactive overlays that shouldn't be reachable from a locked
-- session. Bare Print (no SUPER) stays `locked` so the lockscreen itself
-- (e.g. its clock/wallpaper) can still be captured, same as before.
hl.bind(mainMod .. " + P",        hl.dsp.exec_cmd(screenshot .. " region"))               -- s:  region (current monitor)
hl.bind(mainMod .. " + CTRL + P", hl.dsp.exec_cmd(screenshot .. " region -z"))            -- sf: frozen region
hl.bind(mainMod .. " + ALT + P",  hl.dsp.exec_cmd(screenshot .. " output"))               -- m:  current monitor
hl.bind("Print",                   hl.dsp.exec_cmd("sh -c 'f=~/Pictures/Screenshots/$(date +%Y%m%d-%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim \"$f\" && wl-copy < \"$f\" && notify-send -i \"$f\" Screenshot \"All monitors\"'"), { locked = true }) -- p: all monitors

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind("ALT + Tab",            hl.dsp.focus({ direction = "down" }))

-- Workspaces 1–10 on current monitor (r~N = workspace slot N on this monitor)
for i = 1, 10 do
	local key = tostring(i % 10)
	hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = "r~" .. i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = "r~" .. i }))
	hl.bind(mainMod .. " + ALT + " .. key,   hl.dsp.window.move({ workspace = "r~" .. i, follow = false }))
end

-- Relative workspace navigation
hl.bind(mainMod .. " + CTRL + right", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.focus({ workspace = "empty" }))

-- Resize windows (keyboard, repeating)
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 30,  y = 0,   relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.resize({ x = -30, y = 0,   relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -30, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 30,  relative = true }), { repeating = true })

-- Move window to relative workspace
hl.bind(mainMod .. " + CTRL + ALT + right", hl.dsp.window.move({ workspace = "r+1" }))
hl.bind(mainMod .. " + CTRL + ALT + left",  hl.dsp.window.move({ workspace = "r-1" }))

-- Monitor workspace management
hl.bind(mainMod .. " + CTRL + S", hl.dsp.workspace.swap_monitors({ monitor1 = 0, monitor2 = 1 }))
hl.bind(mainMod .. " + CTRL + 0", hl.dsp.workspace.move({ monitor = 0 }))
hl.bind(mainMod .. " + CTRL + 1", hl.dsp.workspace.move({ monitor = 1 }))

-- Float-aware move: pixels for floating, tile direction for tiled (pure Lua, no shell)
local function floatMove(dx, dy, dir)
	return function()
		local win = hl.get_active_window()
		if win and win.floating then
			hl.dispatch(hl.dsp.window.move({ x = dx, y = dy, relative = true }))
		else
			hl.dispatch(hl.dsp.window.move({ direction = dir }))
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
hl.bind(mainMod .. " + S",       hl.dsp.workspace.toggle_special("scratch"))
hl.bind(mainMod .. " + ALT + S", hl.dsp.window.move({ workspace = "special:scratch", follow = false }))
