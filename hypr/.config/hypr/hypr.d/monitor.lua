-- Laptop panel on the left at 0x0; everything else lines up to its right.
-- The MSI is matched by description, not port, because it shows up as DP-1 or
-- DP-3 depending on which port it's plugged into.

-- Fallback for any other display (projector, TV, …).
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto-right",
	scale = "auto",
	bitdepth = 10,
})

hl.monitor({
	output = "eDP-2",
	mode = "2560x1600@165",
	position = "0x0",
	scale = 1.6,
	bitdepth = 10,
})

hl.monitor({
	output = "desc:Microstep MAG274Q QD E2 CC2HC25300311",
	mode = "2560x1440@180",
	position = "auto-right",
	scale = 1,
	bitdepth = 10,
	-- Wide-gamut QD panel: map sRGB onto its EDID primaries instead of
	-- stretching it (oversaturated). Fullscreen HDR still auto-switches
	-- (render:cm_auto_hdr).
	cm = "edid",
})
