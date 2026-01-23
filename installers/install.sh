#!/bin/sh
#
# install.sh - Installer for intro-fingerprint
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jjangsangy/intro-fingerprint/main/installers/install.sh | sh
#

set -eu

# Configuration
DOWNLOAD_URL="https://github.com/jjangsangy/intro-fingerprint/releases/latest/download/intro-fingerprint.zip"
TEMP_FILE="/tmp/intro-fingerprint-install.zip"
TARGET_PATH="scripts/intro-fingerprint"
BACKUP_NAME=".intro-fingerprint-backup"

# ANSI Colors
if [ -t 1 ]; then
    BLUE='\033[0;34m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    BLUE=''
    GREEN=''
    RED=''
    NC=''
fi

log_info() {
    printf "${BLUE}==>${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}==>${NC} %s\n" "$1"
}

fail() {
    printf "${RED}Error:${NC} %s\n" "$1" >&2
    exit 1
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Determine the MPV configuration directory
detect_config_dir() {
    # Allow override via environment variable
    if [ -n "${MPV_CONFIG_DIR:-}" ]; then
        echo "$MPV_CONFIG_DIR"
        return
    fi

    OS_TYPE="$(uname -s)"

    case "$OS_TYPE" in
        Linux)
            # Check for various package manager locations
            if [ -d "$HOME/.var/app/io.mpv.Mpv/config/mpv" ]; then
                echo "$HOME/.var/app/io.mpv.Mpv/config/mpv"
            elif [ -d "$HOME/snap/mpv/current/.config/mpv" ]; then
                echo "$HOME/snap/mpv/current/.config/mpv"
            elif [ -d "$HOME/snap/mpv-wayland/common/.config/mpv" ]; then
                echo "$HOME/snap/mpv-wayland/common/.config/mpv"
            else
                # Default XDG location
                echo "${XDG_CONFIG_HOME:-$HOME/.config}/mpv"
            fi
            ;;
        Darwin)
            # macOS default
            echo "$HOME/.config/mpv"
            ;;
        *)
            fail "Unsupported operating system: $OS_TYPE"
            ;;
    esac
}

main() {
    # Check dependencies
    if ! has_command curl; then fail "Missing dependency: curl"; fi
    if ! has_command unzip; then fail "Missing dependency: unzip"; fi

    CONFIG_DIR="$(detect_config_dir)"
    INSTALL_DIR="$CONFIG_DIR/$TARGET_PATH"
    BACKUP_DIR="$CONFIG_DIR/$BACKUP_NAME"

    log_info "Target directory: $CONFIG_DIR"

    # Ensure config directory exists
    mkdir -p "$CONFIG_DIR" || fail "Could not create directory: $CONFIG_DIR"

    # Clean up any previous backup
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR" || fail "Could not remove old backup"
    fi

    # Backup existing installation
    if [ -e "$INSTALL_DIR" ]; then
        log_info "Backing up existing installation..."
        mkdir -p "$(dirname "$BACKUP_DIR/$TARGET_PATH")"
        mv "$INSTALL_DIR" "$BACKUP_DIR/$TARGET_PATH" || fail "Backup failed"
    fi

    # Download
    log_info "Downloading..."
    if ! curl -fsSL -o "$TEMP_FILE" "$DOWNLOAD_URL"; then
        # Attempt restore if download fails
        if [ -d "$BACKUP_DIR" ]; then
            log_info "Download failed. Restoring backup..."
            mv "$BACKUP_DIR/$TARGET_PATH" "$INSTALL_DIR"
        fi
        fail "Download failed"
    fi

    # Extract
    log_info "Installing..."
    if ! unzip -qo "$TEMP_FILE" -d "$CONFIG_DIR"; then
        fail "Extraction failed"
    fi

    # Cleanup
    rm -f "$TEMP_FILE"
    rm -rf "$BACKUP_DIR"

    log_success "intro-fingerprint successfully installed."
}

# Run main function
main
