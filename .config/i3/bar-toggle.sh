#!/bin/bash
# Toggle laptop i3bar visibility based on external monitor presence.
# If any external monitor is connected, hide the laptop bar.
# If only the laptop screen is available, show the laptop bar as fallback.

LAPTOP="eDP-1"

# Check if any non-laptop monitor is connected
external_connected=$(xrandr --query | grep -E '^\S+ connected' | grep -v "^${LAPTOP} ")

if [ -n "$external_connected" ]; then
    # External monitor present — hide laptop bar
    i3-msg 'bar mode invisible bar_laptop'
else
    # No external monitor — show laptop bar
    i3-msg 'bar mode hide bar_laptop'
fi
