hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")

-- Hybrid GPU — AMD iGPU is PRIMARY: it renders the compositor AND does VAAPI
-- decode. NVIDIA dGPU is secondary (scanout for monitors wired to it, e.g. the
-- HDMI port, or per-app PRIME offload). AQ_DRM_DEVICES: FIRST device = primary
-- render GPU, so card2 (AMD) leads.
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
-- `lspci | grep -E 'VGA|3D'` and 'ls -l /dev/dri/by-path'
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")

-- NVIDIA cursor fix
hl.config({
	cursor = {
		no_hardware_cursors = true,
	},
})
