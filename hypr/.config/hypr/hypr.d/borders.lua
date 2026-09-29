-- astralis — matugen-themed gradient window borders (active + inactive).
--
-- Reads the live palette straight from ~/.config/hypr/colors.conf (written by
-- matugen on every wallpaper change). matugen's post_hook fires `hyprctl
-- reload`, which re-runs every hypr.d module including this one, so the borders
-- re-theme with the wallpaper — no `source` line needed, we parse the rgba
-- values ourselves. Active = primary → tertiary accent sweep; inactive = a
-- subtle neutral sweep. Loaded AFTER general (so it wins over any border there)
-- and BEFORE astralis-settings, so the LookPage border picker still overrides
-- these when the user explicitly sets a colour.

local function read_palette()
	local home = os.getenv("HOME")
	local path = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/hypr/colors.conf"
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local c = {}
	for line in f:lines() do
		local name, val = line:match("^%$([%w_]+)%s*=%s*(rgba%(%x+%))")
		if name and val then
			c[name] = val
		end
	end
	f:close()
	return c
end

local c = read_palette() or {}
-- Fallbacks keep borders sane on a fresh install before matugen has ever run.
local primary = c.primary or "rgba(b0c6ffff)"
local tertiary = c.tertiary or "rgba(cebef7ff)"
local inactive_a = c.outline_variant or "rgba(434651ff)"
local inactive_b = c.surface_container_high or "rgba(262a34ff)"

-- A gradient in the hl config is a TABLE { colors = {...}, angle = N } — NOT a
-- space-separated string (that routes through the legacy keyword parser, which
-- rejects gradient-typed options: "keyword can't work with non-legacy parsers").
hl.config({
	general = {
		col = {
			active_border = { colors = { primary, tertiary }, angle = 45 },
			inactive_border = { colors = { inactive_a, inactive_b }, angle = 45 },
		},
	},
})
