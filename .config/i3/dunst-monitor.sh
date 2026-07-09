#!/bin/bash
# Set dunst to show notifications on primary monitor, fallback to first connected
OUTPUT=$(xrandr | grep " connected primary" | awk '{print $1}')
if [ -z "$OUTPUT" ]; then
    OUTPUT=$(xrandr | grep " connected" | head -1 | awk '{print $1}')
fi

# Update dunst config and restart
sed -i "s/output = .*/output = $OUTPUT/" ~/.config/dunst/dunstrc
killall dunst 2>/dev/null
nohup dunst &>/dev/null &
exit 0
