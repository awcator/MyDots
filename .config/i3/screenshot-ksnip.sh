#!/bin/bash
mkdir -p ~/Pictures/screenshots

# Get active app name (window class) and sanitize it
raw_app_name=$(xdotool getactivewindow getwindowclassname 2>/dev/null || echo "app")
app_name=$(echo "$raw_app_name" | sed -e 's/[^A-Za-z0-9.]/_/g' -e 's/_\+/_/g' -e 's/^_//' -e 's/_$//')

# Fallback if app_name ends up empty
if [ -z "$app_name" ]; then
    app_name="app"
fi

# Get active window name and sanitize it
raw_window_name=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "desktop")
window_name=$(echo "$raw_window_name" | sed -e 's/[^A-Za-z0-9.]/_/g' -e 's/_\+/_/g' -e 's/^_//' -e 's/_$//')

# Fallback if window_name ends up empty
if [ -z "$window_name" ]; then
    window_name="window"
fi

timestamp=$(date +%Y-%m-%d_%H-%M-%S)

if [ "$1" == "-a" ]; then
    shot_type="active"
    f=~/Pictures/screenshots/${timestamp}_${shot_type}_${app_name}_${window_name}.png
    ksnip -a -p "$f"
    msg="Active window screenshot saved"
else
    shot_type="area"
    f=~/Pictures/screenshots/${timestamp}_${shot_type}_${app_name}_${window_name}.png
    ksnip -r -p "$f"
    msg="Screenshot saved"
fi

# Poll up to 15 seconds waiting for the file to be created
for i in {1..30}; do
    if [ -f "$f" ]; then
        xclip -selection clipboard -t image/png -i "$f"
        notify-send "$msg" "$f"
        break
    fi
    sleep 0.5
done
