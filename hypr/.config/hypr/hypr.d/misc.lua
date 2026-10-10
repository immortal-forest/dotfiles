hl.config({
	misc = {
		-- VRR always on: the panel only refreshes when a frame changes instead of
		-- redrawing at a fixed 165Hz, so an idle desktop costs the iGPU far less.
		-- If the panel flickers at low refresh, use 2 (fullscreen games only).
		vrr = 1,
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		force_default_wallpaper = 0,
		-- Open new windows on the workspace that is active when they MAP, not the
		-- one that was focused when their process launched. Single-instance apps
		-- (ghostty +new-window, zen) otherwise route the new window to the
		-- original launch workspace, so switching workspaces then immediately
		-- spawning (Super+T) landed it on the previous/first workspace.
		initial_workspace_tracking = 0,
	},
})
