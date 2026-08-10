#!/usr/bin/env bash

# Define common flags for yay
YAY_FLAGS=(--removemake --cleanafter --noconfirm --sudoloop)

# 1. Core dependencies to be marked explicitly as --asdeps
DEPS_PACKAGES=(
  hyprland-protocols-git
  hyprwayland-scanner-git
  hyprutils-git
  hyprgraphics-git
  hyprlang-git
  hyprcursor-git
  aquamarine-git
  xdg-desktop-portal-hyprland-git
  hyprwire-git
  hyprtoolkit-git
)

# 2. Main target package
MAIN_PACKAGE="hyprland-git"

# 3. Post-install utilities
ECOSYSTEM_PACKAGES=(
  hypridle-git
  hyprshot-git
  hyprpicker-git
  hyprpolkitagent-git
)

echo "=== Step 1: Installing dependencies in order ==="
for pkg in "${DEPS_PACKAGES[@]}"; do
  echo "--> Building dependency: $pkg"
  yay -S "${YAY_FLAGS[@]}" --asdeps "$pkg" || {
    echo "Failed on $pkg"
    exit 1
  }
done

echo "=== Step 2: Installing core binary ==="
echo "--> Building main package: $MAIN_PACKAGE"
yay -S "${YAY_FLAGS[@]}" "$MAIN_PACKAGE" || {
  echo "Failed on $MAIN_PACKAGE"
  exit 1
}

echo "=== Step 3: Installing user tools in order ==="
for pkg in "${ECOSYSTEM_PACKAGES[@]}"; do
  echo "--> Building utility: $pkg"
  yay -S "${YAY_FLAGS[@]}" "$pkg" || {
    echo "Failed on $pkg"
    exit 1
  }
done

echo "=== System build complete! ==="
