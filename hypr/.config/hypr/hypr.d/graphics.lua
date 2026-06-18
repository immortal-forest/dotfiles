hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")

-- Hybrid GPU — iGPU (AMD) for VAAPI, dGPU (NVIDIA) for rendering
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
-- `lspci | grep -E 'VGA|3D'` and 'ls -l /dev/dri/by-path'
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")

-- NVIDIA cursor fix
hl.config({
	cursor = {
		no_hardware_cursors = true,
	},
})
