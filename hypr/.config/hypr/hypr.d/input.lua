hl.config({
	input = {
		kb_layout = "us",
		numlock_by_default = true,
		follow_mouse = 1,
		sensitivity = 0,
		scroll_factor = 0.5,
		emulate_discrete_scroll = 1,

		touchpad = {
			natural_scroll = true,
		},
	},
})

hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})

hl.device({
	name    = "synps/2-synaptics-touchpad",
	enabled = false,
})
