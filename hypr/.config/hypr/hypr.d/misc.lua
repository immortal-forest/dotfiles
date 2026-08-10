hl.config({
	misc = {
		vrr = 0,
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
