-- Cursor (re-applies on config reload to survive theme resets)
hl.exec_cmd("hyprctl setcursor 'Google.Violet' 24")
hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme 'Google.Violet'")
hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size 24")

-- Fonts
hl.exec_cmd("gsettings set org.gnome.desktop.interface font-name 'Cantarell 10'")
hl.exec_cmd("gsettings set org.gnome.desktop.interface document-font-name 'Cantarell 10'")
hl.exec_cmd("gsettings set org.gnome.desktop.interface monospace-font-name 'CaskaydiaCove Nerd Font Mono 9'")
hl.exec_cmd("gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'")
hl.exec_cmd("gsettings set org.gnome.desktop.interface font-hinting 'full'")

-- Color scheme
hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")

-- Persistent workspaces 1–8 (survive monitor reconnects)
for i = 1, 8 do
	hl.workspace_rule({ workspace = tostring(i), persistent = true })
end
