#!/bin/bash
set -e

# Use current directory (workspace root) as source
WORKSPACE_DIR=$(pwd)
MPV_CONFIG_DIR="$HOME/.config/mpv"

echo "Configuring MPV environment from $WORKSPACE_DIR..."

# Create MPV config structure
mkdir -p "$MPV_CONFIG_DIR/scripts/intro-fingerprint"
mkdir -p "$MPV_CONFIG_DIR/script-opts"

# Symlink files from workspace
# main.lua and modules
ln -sf "$WORKSPACE_DIR/main.lua" "$MPV_CONFIG_DIR/scripts/intro-fingerprint/main.lua"
ln -sf "$WORKSPACE_DIR/modules" "$MPV_CONFIG_DIR/scripts/intro-fingerprint/modules"

# configuration file
# Create a copy with debug=yes instead of symlinking
sed 's/^#debug=no/debug=yes/' "$WORKSPACE_DIR/intro-fingerprint.conf" > "$MPV_CONFIG_DIR/script-opts/intro-fingerprint.conf"

# Create mpv.conf for headless dev environment
cat <<EOF > "$MPV_CONFIG_DIR/mpv.conf"
# DevContainer Config
ao=null
EOF

# Disable default screenshot bindings in devcontainer
# These conflict with the script's Ctrl+s binding (Audio Skip)
cat <<EOF > "$MPV_CONFIG_DIR/input.conf"
s ignore
Ctrl+s script-binding skip-intro-audio
EOF

echo "MPV environment configured successfully at $MPV_CONFIG_DIR"
