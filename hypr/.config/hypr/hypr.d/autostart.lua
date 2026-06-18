hl.on("hyprland.start", function()
	-- XDG portal (screenshare)
	hl.exec_cmd("~/.config/scripts/resetxdgportal.sh")
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")
	hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

	-- Polkit agent
	hl.exec_cmd("systemctl --user start hyprpolkitagent")

	-- Wallpaper daemon
	-- hl.exec_cmd("awww daemon --format argb")

	-- Clipboard history
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")

	-- Shell (TODO: add when quickshell config name is decided)
	-- hl.exec_cmd("qs -c <name>")
end)
