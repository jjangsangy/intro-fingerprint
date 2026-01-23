#!/bin/sh
# POSIX compliant installation script
# Run with: curl -fsSL https://raw.githubusercontent.com/jjangsangy/intro-fingerprint/main/installers/install.sh | sh

zip_url="https://github.com/jjangsangy/intro-fingerprint/releases/latest/download/intro-fingerprint.zip"
zip_file="/tmp/intro-fingerprint.zip"
# Space-separated list of files/directories to manage (relative to config_dir)
files="scripts/intro-fingerprint"
dependencies="curl unzip"

# Exit immediately if a command exits with a non-zero status
set -e

abort() {
    echo "Error: $1"
    echo "Aborting!"

    rm -f "$zip_file"

    # We can't easily iterate and restore specifically in abort for sh without arrays
    # But we can try to restore the whole backup if it exists
    if [ -d "$backup_dir" ]; then
        echo "Restoring backup..."
        # naive restore
        cp -R "$backup_dir/"* "$config_dir/" 2>/dev/null || true
    fi

    exit 1
}

# Check dependencies
missing_dependencies=""
for name in $dependencies; do
    if ! command -v "$name" >/dev/null 2>&1; then
        missing_dependencies="$missing_dependencies $name"
    fi
done

if [ -n "$missing_dependencies" ]; then
    echo "Missing dependencies:$missing_dependencies"
    exit 1
fi

# Determine install directory
os="$(uname)"
config_dir=""

if [ -n "$MPV_CONFIG_DIR" ]; then
    echo "Installing into (MPV_CONFIG_DIR):"
    config_dir="$MPV_CONFIG_DIR"
elif [ "$os" = "Linux" ]; then
    # Flatpak
    if [ -d "$HOME/.var/app/io.mpv.Mpv" ]; then
        echo "Installing into (flatpak io.mpv.Mpv package):"
        config_dir="$HOME/.var/app/io.mpv.Mpv/config/mpv"

    # Snap mpv
    elif [ -d "$HOME/snap/mpv" ]; then
        echo "Installing into (snap mpv package):"
        config_dir="$HOME/snap/mpv/current/.config/mpv"

    # Snap mpv-wayland
    elif [ -d "$HOME/snap/mpv-wayland" ]; then
        echo "Installing into (snap mpv-wayland package):"
        config_dir="$HOME/snap/mpv-wayland/common/.config/mpv"

    # ~/.config
    else
        echo "Config location:"
        # Default XDG_CONFIG_HOME to $HOME/.config if not set
        config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mpv"
    fi
elif [ "$os" = "Darwin" ]; then
    echo "Installing into (macOS default):"
    config_dir="$HOME/.config/mpv"
else
    abort "This install script works only on Linux and macOS."
fi

backup_dir="$config_dir/.intro-fingerprint-backup"

echo "Target: $config_dir"
mkdir -p "$config_dir" || abort "Couldn't create config directory."

echo "Backing up..."
rm -rf "$backup_dir" || abort "Couldn't cleanup backup directory."

# Backup existing files
for file in $files; do
    from_path="$config_dir/$file"
    if [ -e "$from_path" ]; then
        to_path="$backup_dir/$file"
        to_dir="$(dirname "$to_path")"
        mkdir -p "$to_dir" || abort "Couldn't create backup folder: $to_dir"
        mv "$from_path" "$to_path" || abort "Couldn't move '$from_path' to '$to_path'."
    fi
done

# Install new version
echo "Downloading archive..."
curl -Ls -o "$zip_file" "$zip_url" || abort "Couldn't download: $zip_url"

echo "Extracting archive..."
# unzip arguments: -q (quiet), -o (overwrite), -d (destination directory)
unzip -qo -d "$config_dir" "$zip_file" || abort "Couldn't extract: $zip_file"

echo "Deleting archive..."
rm -f "$zip_file" || echo "Couldn't delete: $zip_file"

echo "Deleting backup..."
rm -rf "$backup_dir" || echo "Couldn't delete: $backup_dir"

echo "intro-fingerprint has been installed."
