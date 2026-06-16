#!/bin/bash
# gencc.sh - Generate compile_commands.json for clangd
# Usage: gencc.sh [options] [make targets...]
set -euo pipefail
CLEAN_CACHE=true
TARGETS=()
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
usage() {
  echo "Usage: gencc.sh [options] [make targets...]"
  echo ""
  echo "Options:"
  echo "  --no-clean    Skip clearing clangd cache"
  echo "  -h, --help    Show this help message"
  echo ""
  echo "Examples:"
  echo "  gencc.sh                        # auto-detect, default target"
  echo "  gencc.sh run shared library     # specific make targets"
  echo "  gencc.sh --no-clean             # keep clangd cache"
  exit 0
}
# Parse arguments
for arg in "$@"; do
  case $arg in
  --no-clean)
    CLEAN_CACHE=false
    ;;
  -h | --help)
    usage
    ;;
  *)
    TARGETS+=("$arg")
    ;;
  esac
done
# Check dependencies
for cmd in bear jq; do
  if ! command -v $cmd &>/dev/null; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    echo "Install with: sudo pacman -S $cmd"
    exit 1
  fi
done
# Generate compile_flags.txt from compile_commands.json
generate_compile_flags() {
  if [[ -f "compile_flags.txt" ]]; then
    echo -e "${YELLOW}compile_flags.txt already exists, skipping${NC}"
    return
  fi

  if [[ ! -f "compile_commands.json" ]]; then
    return
  fi

  echo "Generating compile_flags.txt as fallback..."

  # Extract common flags from first entry
  jq -r '.[0].arguments | .[] | select(startswith("-") and (startswith("-o") | not) and (. != "gcc") and (. != "g++") and (. != "clang") and (. != "clang++") and (contains("/") | not))' compile_commands.json 2>/dev/null | sort -u >compile_flags.txt

  if [[ -s "compile_flags.txt" ]]; then
    echo -e "${GREEN}Created compile_flags.txt with $(wc -l <compile_flags.txt) flags${NC}"
  else
    rm -f compile_flags.txt
  fi
}
# Detect build system and generate compile_commands.json
if [[ -f "CMakeLists.txt" ]]; then
  echo "Detected CMake project"
  mkdir -p build && cd build
  cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..
  cd ..
  ln -sf build/compile_commands.json . 2>/dev/null || cp build/compile_commands.json .

elif [[ -f "Makefile" ]] || [[ -f "makefile" ]]; then
  echo "Detected Makefile project"

  rm -f compile_commands.json

  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "Building default target..."
    bear -- make
  else
    echo "Building targets: ${TARGETS[*]}"
    bear -- make "${TARGETS[@]}"
  fi

  # Deduplicate entries
  if [[ -f "compile_commands.json" ]]; then
    echo "Deduplicating compile_commands.json..."
    jq 'unique_by(.file)' compile_commands.json >temp_compile_commands.json
    mv temp_compile_commands.json compile_commands.json
    echo -e "${GREEN}Done: $(jq length compile_commands.json) unique entries${NC}"
  fi

elif [[ -f "meson.build" ]]; then
  echo "Detected Meson project"
  meson setup build --wipe 2>/dev/null || meson setup build
  ln -sf build/compile_commands.json . 2>/dev/null || true

else
  echo -e "${RED}Error: No supported build system found (CMake, Make, Meson)${NC}"
  exit 1
fi
# Generate compile_flags.txt fallback
generate_compile_flags
# Clear clangd cache
if [[ "$CLEAN_CACHE" == true ]] && [[ -d ".cache/clangd" ]]; then
  echo "Clearing clangd cache..."
  rm -rf .cache/clangd/index
fi
echo -e "${GREEN}Done! Restart Neovim for clangd to re-index.${NC}"
