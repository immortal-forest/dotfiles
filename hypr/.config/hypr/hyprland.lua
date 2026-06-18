-- Lua converts '.' to '/' in require paths, so "hypr.d/apps" resolves to
-- "hypr/d/apps.lua" instead of "hypr.d/apps.lua". Fix: add hypr.d/ directly.
local configHome = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
package.path = configHome .. "/hypr/hypr.d/?.lua;" .. package.path

local modules = {
	"apps",
	"env",
	"graphics",
	"monitor",
	"general",
	"decorations",
	"animations",
	"layout",
	"misc",
	"input",
	"autostart",
	"keybinds",
	"windows",
	"userpref",
	"extra",
}

for _, mod in ipairs(modules) do
	local ok, err = pcall(require, mod)
	if not ok then
		print("[hypr.d] failed to load " .. mod .. ": " .. err)
	end
end
