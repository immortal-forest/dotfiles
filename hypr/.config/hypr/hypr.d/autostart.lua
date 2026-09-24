hl.on("hyprland.start", function()
	-- XDG portal (screenshare)
	hl.exec_cmd("~/.config/scripts/resetxdgportal.sh")
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")
	hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

	-- Polkit agent
	hl.exec_cmd("systemctl --user start hyprpolkitagent")

	-- Wallpaper: skwd-paper (standalone daemon) is the render backend; its CLI
	-- auto-spawns the daemon on first `apply`. This restore script displays the
	-- cached wallpaper via skwd-paper and re-themes astralis (matugen) from it.
	hl.exec_cmd("~/.local/bin/restore-wallpaper.sh")

	-- Clipboard history
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")

	-- Shell (astralis). Respawn loop: qs can abort on suspend/resume
	-- (quickshell #1155). Restart on crash, break on clean quit, back off 5s on
	-- a fast crash-loop so a broken config can't spin the CPU.
	hl.exec_cmd("bash -c 'while true; do t=$(date +%s); qs -c astralis; [ $? -eq 0 ] && break; [ $(( $(date +%s) - t )) -lt 5 ] && sleep 5 || sleep 1; done'")
end)
