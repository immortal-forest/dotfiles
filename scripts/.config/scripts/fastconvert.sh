fastconvert() {
  if [ -z "$1" ]; then
    echo "Error: Please specify an input video file."
    echo "Usage: fastconvert video.mp4"
    return 1
  fi

  # Create output name based on input filename
  local input_file="$1"
  local output_file="${input_file%.*}_encoded.mp4"

  echo "🚀 Initializing Hyper-Speed NVIDIA NVENC Encoding Pipeline..."

  # Force PRIME offload environmental layers directly onto FFmpeg
  __NV_PRIME_RENDER_OFFLOAD=1 \
    __GLX_VENDOR_LIBRARY_NAME=nvidia \
    ffmpeg -i "$input_file" \
    -c:v hevc_nvenc -preset p4 -tune hq -b:v 65M -maxrate 80M -bufsize 100M \
    -pix_fmt yuv420p -tag:v hvc1 -force_fps -fps_mode cfr \
    -c:a aac -b:a 320k \
    "$output_file"

  echo "✅ Done! Saved as: $output_file"
}
