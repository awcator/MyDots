#!/bin/bash
# setup-sunshine-virtual-display.sh
# Sets up a headless NVIDIA virtual display for Sunshine/Moonlight streaming
# Assumes: plain eDP laptop, NVIDIA Optimus, Arch Linux, X11
#
# What it does:
#   1. Installs xf86-video-dummy (optional, not used in current approach)
#   2. Copies NVIDIA xorg config that forces a virtual display via ConnectedMonitor
#   3. Copies EDID file for the virtual display
#   4. Sets up Sunshine config for X11 capture
#   5. Installs sunshinemode script
#
# After setup, restart X session. Then run `sunshinemode` to start streaming.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XORG_CONF_DIR="/etc/X11/xorg.conf.d"
EDID_DIR="/etc/X11"

echo "=== Sunshine Virtual Display Setup ==="

# Backup existing nvidia config
if [ -f "$XORG_CONF_DIR/10-nvidia-primary.conf" ]; then
    sudo cp "$XORG_CONF_DIR/10-nvidia-primary.conf" "$XORG_CONF_DIR/10-nvidia-primary.conf.bak.$(date +%s)"
    echo "Backed up existing nvidia config"
fi

# Install xorg config
sudo cp "$SCRIPT_DIR/xorg.conf.d/10-nvidia-primary.conf" "$XORG_CONF_DIR/"
echo "Installed 10-nvidia-primary.conf"

# Install EDID
sudo cp "$SCRIPT_DIR/../edid-virtual.bin" "$EDID_DIR/"
echo "Installed edid-virtual.bin"

# Install sunshine.conf
mkdir -p "$HOME/.config/sunshine"
if [ ! -f "$HOME/.config/sunshine/sunshine.conf" ]; then
    cp "$SCRIPT_DIR/../sunshine.conf.reference" "$HOME/.config/sunshine/sunshine.conf"
    echo "Installed sunshine.conf"
else
    echo "sunshine.conf already exists, skipping (reference at $SCRIPT_DIR/../sunshine.conf.reference)"
fi

# sunshinemode script should already be in ~/bin via dotfiles

echo ""
echo "=== Done ==="
echo "Restart your X session, then run 'sunshinemode' to start streaming."
echo ""
echo "NVIDIA xorg config forces DFP-0 (real monitor) + DFP-1 (virtual) as connected."
echo "DFP-1 uses a fake EDID so NVIDIA thinks a monitor is plugged in."
echo "sunshinemode enables the virtual display, detects its Sunshine ID, and launches Sunshine."
echo "Ctrl+C sunshinemode to stop and revert to normal desktop."
