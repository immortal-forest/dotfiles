-- astralis settings overlay loader.
--
-- The astralis shell's 設 SETTINGS surface persists Hyprland-keyword settings
-- (animations, gaps, blur, …) two ways: live via `hyprctl keyword`, and into
-- a generated Lua overlay at ~/.cache/astralis/hypr-settings.lua so they
-- survive `hyprctl reload`. This stub sources that overlay; it is required
-- LAST in hyprland.lua's module list so shell-edited settings override the
-- hand-written hypr.d values (last-wins), while every file in this directory
-- stays hand-authored. Delete the cache file to revert to the config as
-- written here. Generator: quickshell/astralis/services/Settings.qml.

local overlay = (os.getenv("HOME") or "") .. "/.cache/astralis/hypr-settings.lua"
local f = io.open(overlay, "r")
if f then
	f:close()
	local ok, err = pcall(dofile, overlay)
	if not ok then
		print("[astralis-settings] overlay failed: " .. tostring(err))
	end
end
