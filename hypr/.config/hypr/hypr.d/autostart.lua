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
	-- MALLOC_CONF: qs links jemalloc, which defaults to 4 arenas per CPU (64 on
	-- this box) and each one hoards freed pages — ~60MB of dead heap. 4 arenas +
	-- fast decay keeps the same shell at ~100MB anon instead of ~160MB.
	-- --log-rules: Quickshell re-reads IconName on every tray NewIcon even when
	-- the app has no such property (Electron/Discord), so each icon flip logged
	-- two warnings — nonstop during a voice call, into a log that lives in
	-- /run (RAM).
	-- Keep in sync with the Super+Shift+R relaunch bind in keybinds.lua.
	hl.exec_cmd("bash -c 'export MALLOC_CONF=narenas:4,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0; while true; do t=$(date +%s); qs -c astralis --log-rules quickshell.dbus.properties.warning=false; [ $? -eq 0 ] && break; [ $(( $(date +%s) - t )) -lt 5 ] && sleep 5 || sleep 1; done'")
end)
