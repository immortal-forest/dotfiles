-- XWayland scaling fix (prevents blurry X11 apps)
hl.config({
	xwayland = {
		force_zero_scaling = true,
	},
})
