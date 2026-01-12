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
# main.lua
ln -sf "$WORKSPACE_DIR/main.lua" "$MPV_CONFIG_DIR/scripts/intro-fingerprint/main.lua"

# libs directory
ln -sfn "$WORKSPACE_DIR/libs" "$MPV_CONFIG_DIR/scripts/intro-fingerprint/libs"

# configuration file
ln -sf "$WORKSPACE_DIR/intro-fingerprint.conf" "$MPV_CONFIG_DIR/script-opts/intro-fingerprint.conf"

echo "MPV environment configured successfully at $MPV_CONFIG_DIR"
